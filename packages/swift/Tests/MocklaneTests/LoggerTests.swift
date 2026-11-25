import XCTest
@testable import Mocklane

final class LogCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?
    private var _body: Data?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _request
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _body
    }

    func store(_ request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        _request = request
        _body = body
    }
}

/// URLProtocol stub that captures the request instead of hitting a socket.
final class LogCaptureURLProtocol: URLProtocol {
    static let captured = LogCaptureBox()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession converts `httpBody` into `httpBodyStream` before the
        // request reaches a URLProtocol, so read whichever is present.
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            body = data
        }
        Self.captured.store(request, body: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// URLProtocol stub that always fails, to exercise the never-throw path.
final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: 1))
    }

    override func stopLoading() {}
}

final class LoggerTests: XCTestCase {
    func testHttpTransportPostsMaskedJsonWithDeviceHeaders() async throws {
        let config = MocklaneConfig(
            host: "127.0.0.1",
            port: 6625,
            device: DeviceMetadata(deviceId: "swift-test", deviceName: "swift-log"),
            enabled: true
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [LogCaptureURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let transport = HttpLoggerTransport(config: config, session: session)
        await transport.send(
            message: "{\"user\":\"a\",\"password\":\"hunter2\"}",
            level: .info,
            tag: "home"
        )

        let captured = try XCTUnwrap(LogCaptureURLProtocol.captured.request)
        XCTAssertEqual(captured.url?.path, "/__mocklane/v1/log")
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "X-Mocklane-Device-Id"), "swift-test")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "X-Mocklane-Device-Name"), "swift-log")
        XCTAssertTrue(
            captured.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") ?? false
        )

        let body = try XCTUnwrap(LogCaptureURLProtocol.captured.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Compare the masked message semantically: JSON object key order is
        // not significant (and re-serialization sorts keys).
        let message = try XCTUnwrap(json["message"] as? String)
        let masked = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any]
        )
        XCTAssertEqual(masked["user"] as? String, "a")
        XCTAssertEqual(masked["password"] as? String, "[REDACTED]")
        XCTAssertEqual(json["level"] as? String, "info")
        XCTAssertEqual(json["tag"] as? String, "home")
        XCTAssertEqual((json["device"] as? [String: String])?["deviceId"], "swift-test")
        XCTAssertEqual((json["device"] as? [String: String])?["deviceName"], "swift-log")
    }

    func testLoggerForwardsMessageLevelAndTag() {
        final class Capturing: LoggerTransport, @unchecked Sendable {
            var captured: (String, LogLevel, String?)?
            func send(message: String, level: LogLevel, tag: String?) async {
                captured = (message, level, tag)
            }
        }
        let capturing = Capturing()
        Logger(transport: capturing).log("hello", level: .warn, tag: "home")

        let sent = expectation(description: "log sent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sent.fulfill() }
        wait(for: [sent], timeout: 1.0)

        XCTAssertEqual(capturing.captured?.0, "hello")
        XCTAssertEqual(capturing.captured?.1, .warn)
        XCTAssertEqual(capturing.captured?.2, "home")
    }

    func testHttpTransportSwallowsSessionErrors() async {
        let config = MocklaneConfig(host: "127.0.0.1", port: 6625, enabled: true)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FailingURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let transport = HttpLoggerTransport(config: config, session: session)
        await transport.send(message: "hello", level: .info, tag: nil) // must not throw
    }
}
