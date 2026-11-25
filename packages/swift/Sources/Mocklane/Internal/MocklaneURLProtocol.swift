import Foundation

/// URLProtocol that rewrites absolute http(s) requests through the gateway.
///
/// Installed by `Mocklane.urlSession(...)`; do not register it globally.
final class MocklaneURLProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var probeTask: Task<Void, Never>?
    private var forwardTask: URLSessionDataTask?
    private var stopped = false
    private var finished = false
    /// A 3xx response is held back until the forwarder decides whether to
    /// follow it. Following hops must stay hidden from the app's delegate;
    /// unfollowed ones (no `Location`, redirects disabled) are delivered as-is.
    private var pendingRedirect: HTTPURLResponse?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let runtime = Mocklane.runtimeOrNil else { return false }
        guard !UnsupportedProtocols.shouldSkip(request) else { return false }
        guard let url = request.url,
              let host = url.host,
              !host.isEmpty,
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        guard scheme == "http" || scheme == "https" else { return false }
        // Never intercept probe/log/already-rewritten gateway calls (avoids recursion).
        if MocklaneRewrite.isGatewayURL(
            url.absoluteString,
            host: runtime.config.host,
            port: runtime.config.port
        ) {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let runtime = Mocklane.runtimeOrNil else {
            finish(error: URLError(.unknown))
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.load(runtime: runtime)
        }

        lock.lock()
        if stopped {
            lock.unlock()
            task.cancel()
            return
        }
        probeTask = task
        lock.unlock()
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        let probe = probeTask
        probeTask = nil
        let forward = forwardTask
        forwardTask = nil
        lock.unlock()
        probe?.cancel()
        forward?.cancel()
    }

    // MARK: - Forwarder callbacks

    func receive(response: URLResponse) {
        lock.lock()
        if stopped || finished {
            lock.unlock()
            return
        }
        if let http = response as? HTTPURLResponse,
           (300..<400).contains(http.statusCode),
           http.value(forHTTPHeaderField: "Location") != nil {
            pendingRedirect = http
            lock.unlock()
            return
        }
        lock.unlock()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func receive(data: Data) {
        lock.lock()
        let blocked = stopped || finished || pendingRedirect != nil
        lock.unlock()
        guard !blocked else { return }
        client?.urlProtocol(self, didLoad: data)
    }

    /// The forwarder is following the pending redirect itself; drop the 3xx.
    func redirectFollowed() {
        lock.lock()
        pendingRedirect = nil
        lock.unlock()
    }

    func finish(error: Error?) {
        lock.lock()
        if stopped || finished {
            lock.unlock()
            return
        }
        finished = true
        let pending = pendingRedirect
        pendingRedirect = nil
        lock.unlock()

        if let pending {
            // The forwarding session did not follow this redirect; the app
            // sees it as the final response, exactly as a plain session would.
            client?.urlProtocol(self, didReceive: pending, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    // MARK: - Loading

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func load(runtime: Mocklane.Runtime) async {
        let original = request
        guard let originalURL = original.url else {
            finish(error: URLError(.badURL))
            return
        }

        let reachable = await runtime.probe.isReachable()
        if Task.isCancelled || isStopped { return }

        var prepared = original
        if prepared.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = runtime.forwarder.cookieHeader(for: originalURL) {
            prepared.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        if !reachable {
            if runtime.config.failOpen {
                forward(
                    prepared,
                    originalURL: originalURL,
                    runtime: runtime,
                    proxied: false
                )
            } else {
                finish(
                    error: URLError(
                        .cannotConnectToHost,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Mocklane gateway unreachable at \(runtime.config.host):\(runtime.config.port)",
                        ]
                    )
                )
            }
            return
        }

        var proxiedRequest = prepared
        proxiedRequest.url = MocklaneRewrite.rewriteToGateway(
            originalURL,
            host: runtime.config.host,
            port: runtime.config.port
        )
        DeviceHeaders.apply(runtime.config.device, to: &proxiedRequest)
        forward(
            proxiedRequest,
            originalURL: originalURL,
            runtime: runtime,
            proxied: true
        )
    }

    private func forward(
        _ request: URLRequest,
        originalURL: URL,
        runtime: Mocklane.Runtime,
        proxied: Bool
    ) {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        lock.unlock()

        let task = runtime.forwarder.start(
            request,
            owner: self,
            originalURL: originalURL,
            proxied: proxied
        )

        // `stopLoading` may have run while the task was being created.
        lock.lock()
        if stopped {
            lock.unlock()
            task.cancel()
            return
        }
        forwardTask = task
        lock.unlock()
    }
}
