import Foundation

/// One forwarding session per runtime.
///
/// A `URLProtocol` subclass has to fetch the response itself. A single,
/// long-lived session per runtime keeps connections alive, and the data
/// delegate streams each chunk to the owning protocol instance — `data(for:)`
/// buffered whole responses and hid SSE / long-poll traffic until the stream
/// closed.
final class Forwarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Entry: @unchecked Sendable {
        weak var owner: MocklaneURLProtocol?
        /// The origin URL the app asked for. Redirects update it so cookies and
        /// relative `Location` headers stay attached to the original origin,
        /// not to the gateway (which only ever sees rewritten URLs).
        var originalURL: URL
        /// `false` on the fail-open path: the request goes straight to the
        /// origin, so redirect targets must not be rewritten to the gateway.
        let proxied: Bool

        init(owner: MocklaneURLProtocol, originalURL: URL, proxied: Bool) {
            self.owner = owner
            self.originalURL = originalURL
            self.proxied = proxied
        }
    }

    private let config: MocklaneConfig
    private let cookieStorage: HTTPCookieStorage?
    private let usesCookies: Bool
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var session: URLSession!

    init(configuration: URLSessionConfiguration, config: MocklaneConfig) {
        self.config = config
        self.cookieStorage = configuration.httpCookieStorage
        self.usesCookies = configuration.httpShouldSetCookies
        super.init()

        let forward = (configuration.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.ephemeral
        // A custom URLProtocol bypasses URLSession's own cookie machinery, so
        // cookies are mirrored manually against the origin. Letting the inner
        // session also store them would key every cookie to the gateway host.
        forward.protocolClasses = []
        forward.httpCookieStorage = nil
        forward.httpShouldSetCookies = false
        // A cache hit would never reach the gateway and so never be captured.
        forward.urlCache = nil
        forward.requestCachePolicy = .reloadIgnoringLocalCacheData

        session = URLSession(configuration: forward, delegate: self, delegateQueue: nil)
    }

    func start(
        _ request: URLRequest,
        owner: MocklaneURLProtocol,
        originalURL: URL,
        proxied: Bool
    ) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        lock.lock()
        entries[task.taskIdentifier] = Entry(
            owner: owner,
            originalURL: originalURL,
            proxied: proxied
        )
        lock.unlock()
        task.resume()
        return task
    }

    /// `Cookie` header value for `url` from the app's cookie storage, if any.
    ///
    /// The inner session never sees the origin host, so the SDK has to attach
    /// the header itself before rewriting the URL to the gateway.
    func cookieHeader(for url: URL) -> String? {
        guard usesCookies, let cookieStorage else { return nil }
        let cookies = cookieStorage.cookies(for: url) ?? []
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    func invalidate() {
        session.finishTasksAndInvalidate()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let entry = entry(for: dataTask) {
            storeCookies(from: response, for: entry.originalURL)
            entry.owner?.receive(response: response)
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        entry(for: dataTask)?.owner?.receive(data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let entry = entries.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        entry?.owner?.finish(error: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let entry = entry(for: task) else {
            completionHandler(request)
            return
        }
        entry.owner?.redirectFollowed()
        // Darwin does not deliver redirect responses to `didReceive response`,
        // so their Set-Cookie has to be stored here.
        storeCookies(from: response, for: entry.originalURL)

        // URLSession resolves relative locations against the forwarded URL,
        // which points at the gateway. Resolve against the original origin
        // instead, then bring the hop back through the gateway so it is
        // captured and keeps the origin-prefixed form.
        var next = request
        if let location = response.value(forHTTPHeaderField: "Location"),
           let resolved = URL(string: location, relativeTo: entry.originalURL)?.absoluteURL {
            next.url = resolved
        }
        if let url = next.url, isWebURL(url) {
            // Every hop goes through the same gateway, so URLSession cannot
            // see a cross-origin redirect on its own and would keep credentials
            // the app never meant to send to the new origin.
            if !sameOrigin(url, entry.originalURL) {
                next.setValue(nil, forHTTPHeaderField: "Authorization")
                next.setValue(nil, forHTTPHeaderField: "Cookie")
            }
            if next.value(forHTTPHeaderField: "Cookie") == nil,
               let cookie = cookieHeader(for: url) {
                next.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            if entry.proxied {
                next.url = MocklaneRewrite.rewriteToGateway(
                    url,
                    host: config.host,
                    port: config.port
                )
                DeviceHeaders.apply(config.device, to: &next)
            }
            lock.lock()
            entry.originalURL = url
            lock.unlock()
        }
        completionHandler(next)
    }

    // MARK: - Private

    private func entry(for task: URLSessionTask) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[task.taskIdentifier]
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let leftScheme = lhs.scheme?.lowercased(),
              let rightScheme = rhs.scheme?.lowercased(),
              let leftHost = lhs.host?.lowercased(),
              let rightHost = rhs.host?.lowercased()
        else { return false }
        return leftScheme == rightScheme
            && leftHost == rightHost
            && defaultPort(lhs) == defaultPort(rhs)
    }

    private func defaultPort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }

    private func storeCookies(from response: URLResponse, for url: URL) {
        guard usesCookies,
              let cookieStorage,
              let http = response as? HTTPURLResponse
        else { return }

        var header: String?
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String,
                  name.caseInsensitiveCompare("Set-Cookie") == .orderedSame
            else { continue }
            let joined: String?
            if let values = value as? [String] {
                joined = values.joined(separator: ", ")
            } else {
                joined = value as? String
            }
            guard let joined else { continue }
            header = header.map { $0 + ", " + joined } ?? joined
        }
        guard let header else { return }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": header],
            for: url
        )
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
    }
}
