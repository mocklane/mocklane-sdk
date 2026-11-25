import XCTest
@testable import Mocklane

#if os(macOS)
    import Darwin
    import Dispatch

    /// Minimal blocking HTTP/1.1 server for forwarding tests.
    ///
    /// The SDK rewrites every origin URL to `<host>:<port>/<origin URL>`, so
    /// this server stands in for the gateway and dispatches on the rewritten
    /// path. It only needs GET with no body.
    private final class TestHTTPServer: @unchecked Sendable {
        struct Request {
            let method: String
            let path: String
            let headers: [String: String]

            func value(for name: String) -> String? {
                headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
        }

        let port: UInt16
        private let listenFd: Int32
        private let queue = DispatchQueue(label: "mocklane.test.server")
        private let handler: (Request, Int32) -> Void
        private let lock = NSLock()
        private var stopped = false

        init(handler: @escaping (Request, Int32) -> Void) throws {
            self.handler = handler

            let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { throw POSIXError(.EMFILE) }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bound: Bool = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            guard bound, Darwin.listen(fd, 16) == 0 else {
                Darwin.close(fd)
                throw POSIXError(.EADDRINUSE)
            }

            var boundAddr = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named: Bool = withUnsafeMutablePointer(to: &boundAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(fd, $0, &length) == 0
                }
            }
            guard named else {
                Darwin.close(fd)
                throw POSIXError(.EINVAL)
            }

            self.listenFd = fd
            self.port = UInt16(bigEndian: boundAddr.sin_port)
            queue.async { [weak self] in self?.acceptLoop() }
        }

        deinit {
            stop()
        }

        func stop() {
            lock.lock()
            if stopped {
                lock.unlock()
                return
            }
            stopped = true
            lock.unlock()
            Darwin.shutdown(listenFd, SHUT_RDWR)
            Darwin.close(listenFd)
        }

        static func write(_ fd: Int32, _ string: String) {
            let bytes = Array(string.utf8)
            var offset = 0
            while offset < bytes.count {
                let chunk = Array(bytes[offset...])
                let written = chunk.withUnsafeBytes {
                    Darwin.send(fd, $0.baseAddress, $0.count, 0)
                }
                if written <= 0 { return }
                offset += written
            }
        }

        static func respond(
            _ fd: Int32,
            status: String = "200 OK",
            headers: [String: String] = [:],
            body: String
        ) {
            var head =
                "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
            for (name, value) in headers {
                head += "\(name): \(value)\r\n"
            }
            head += "\r\n"
            write(fd, head + body)
        }

        private func acceptLoop() {
            while true {
                let client = Darwin.accept(listenFd, nil, nil)
                guard client >= 0 else { return }
                var yes: Int32 = 1
                setsockopt(
                    client,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    &yes,
                    socklen_t(MemoryLayout<Int32>.size)
                )
                if let request = readRequest(client) {
                    handler(request, client)
                }
                Darwin.close(client)
            }
        }

        private func readRequest(_ fd: Int32) -> Request? {
            var buffer = [UInt8]()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while buffer.count < 1 << 16 {
                let count = chunk.withUnsafeMutableBytes {
                    Darwin.read(fd, $0.baseAddress, $0.count)
                }
                guard count > 0 else { return nil }
                buffer.append(contentsOf: chunk[0..<count])
                if buffer.count >= 4,
                   buffer[(buffer.count - 4)...].elementsEqual([13, 10, 13, 10]) {
                    break
                }
            }

            guard let text = String(bytes: buffer, encoding: .utf8),
                  let end = text.range(of: "\r\n\r\n")
            else { return nil }

            var lines = String(text[..<end.lowerBound]).components(separatedBy: "\r\n")
            guard !lines.isEmpty else { return nil }
            let requestLine = lines.removeFirst().split(separator: " ")
            guard requestLine.count >= 2 else { return nil }

            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon])
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
            return Request(
                method: String(requestLine[0]),
                path: String(requestLine[1]),
                headers: headers
            )
        }
    }

    final class ForwarderTests: XCTestCase {
        override func tearDown() {
            Mocklane.reset()
            super.tearDown()
        }

        private func makeSession(server: TestHTTPServer) -> URLSession {
            Mocklane.makeSession(
                config: MocklaneConfig(
                    host: "127.0.0.1",
                    port: Int(server.port),
                    enabled: true
                ),
                configuration: .ephemeral,
                probe: AlwaysReachableProbe()
            )
        }

        func testStreamsChunksBeforeCompletion() async throws {
            let gate = DispatchSemaphore(value: 0)
            let server = try TestHTTPServer { request, fd in
                guard request.path == "/https://api.example.com/stream" else {
                    TestHTTPServer.respond(fd, status: "404 Not Found", body: "")
                    return
                }
                TestHTTPServer.write(
                    fd,
                    "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n"
                        + "Content-Type: text/plain\r\nConnection: close\r\n\r\nfirst"
                )
                _ = gate.wait(timeout: .now() + 10)
                TestHTTPServer.write(fd, "second")
            }
            defer { server.stop() }

            let session = makeSession(server: server)
            let (bytes, response) = try await session.bytes(
                from: URL(string: "https://api.example.com/stream")!
            )
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            var iterator = bytes.makeAsyncIterator()

            // The server holds the last six bytes until the test has seen the
            // first five, so the data can only arrive streamed.
            var first = ""
            for _ in 0..<5 {
                guard let byte = try await iterator.next() else {
                    XCTFail("stream ended before the first chunk")
                    return
                }
                first.append(Character(UnicodeScalar(byte)))
            }
            XCTAssertEqual(first, "first")
            gate.signal()

            var second = ""
            for _ in 0..<6 {
                guard let byte = try await iterator.next() else {
                    XCTFail("stream ended before the second chunk")
                    return
                }
                second.append(Character(UnicodeScalar(byte)))
            }
            XCTAssertEqual(second, "second")
        }

        func testRelativeRedirectStaysOnOrigin() async throws {
            let lock = NSLock()
            var paths: [String] = []
            let server = try TestHTTPServer { request, fd in
                lock.lock()
                paths.append(request.path)
                lock.unlock()
                switch request.path {
                case "/https://api.example.com/start":
                    TestHTTPServer.respond(
                        fd,
                        status: "302 Found",
                        headers: ["Location": "/final"],
                        body: ""
                    )
                case "/https://api.example.com/final":
                    TestHTTPServer.respond(fd, body: "ok")
                default:
                    TestHTTPServer.respond(fd, status: "404 Not Found", body: "")
                }
            }
            defer { server.stop() }

            let session = makeSession(server: server)
            let (data, response) = try await session.data(
                from: URL(string: "https://api.example.com/start")!
            )

            XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            lock.lock()
            let seen = paths
            lock.unlock()
            // The relative Location resolves against the origin, then goes
            // back through the gateway so the hop is captured too.
            XCTAssertEqual(
                seen,
                ["/https://api.example.com/start", "/https://api.example.com/final"]
            )
        }

        func testCookiesRoundTripAgainstOrigin() async throws {
            removeCookies(for: "api.example.com")
            defer { removeCookies(for: "api.example.com") }

            let cookieHeader = LockedValue<String>()
            let server = try TestHTTPServer { request, fd in
                switch request.path {
                case "/https://api.example.com/set-cookie":
                    TestHTTPServer.respond(
                        fd,
                        headers: ["Set-Cookie": "sid=abc; Path=/"],
                        body: "set"
                    )
                case "/https://api.example.com/needs-cookie":
                    cookieHeader.set(request.value(for: "Cookie"))
                    TestHTTPServer.respond(fd, body: "ok")
                default:
                    TestHTTPServer.respond(fd, status: "404 Not Found", body: "")
                }
            }
            defer { server.stop() }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = HTTPCookieStorage.shared
            let session = Mocklane.makeSession(
                config: MocklaneConfig(
                    host: "127.0.0.1",
                    port: Int(server.port),
                    enabled: true
                ),
                configuration: configuration,
                probe: AlwaysReachableProbe()
            )

            _ = try await session.data(
                from: URL(string: "https://api.example.com/set-cookie")!
            )
            let origin = URL(string: "https://api.example.com/")!
            let stored = HTTPCookieStorage.shared.cookies(for: origin) ?? []
            XCTAssertTrue(
                stored.contains { $0.name == "sid" && $0.value == "abc" },
                "Set-Cookie should be stored against the origin, got \(stored)"
            )

            _ = try await session.data(
                from: URL(string: "https://api.example.com/needs-cookie")!
            )
            XCTAssertEqual(cookieHeader.get(), "sid=abc")
        }

        func testCancellationStopsForwarding() async throws {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let server = try TestHTTPServer { _, fd in
                TestHTTPServer.write(
                    fd,
                    "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n"
                        + "Content-Type: text/plain\r\nConnection: close\r\n\r\nstarted"
                )
                started.signal()
                _ = release.wait(timeout: .now() + 10)
            }
            defer { server.stop() }

            let session = makeSession(server: server)
            let task = Task { () -> Data in
                let (data, _) = try await session.data(
                    from: URL(string: "https://api.example.com/slow")!
                )
                return data
            }

            switch started.wait(timeout: .now() + 10) {
            case .success:
                break
            case .timedOut:
                XCTFail("server never received the forwarded request")
                task.cancel()
                release.signal()
                return
            }
            task.cancel()
            let result = await task.result
            release.signal()

            switch result {
            case .success:
                XCTFail("cancelled request completed")
            case .failure(let error):
                XCTAssertEqual((error as? URLError)?.code, .cancelled)
            }
        }

        private func removeCookies(for domain: String) {
            let storage = HTTPCookieStorage.shared
            for cookie in storage.cookies ?? [] where cookie.domain.hasSuffix(domain) {
                storage.deleteCookie(cookie)
            }
        }
    }

    private final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value?

        func set(_ value: Value?) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> Value? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
#endif
