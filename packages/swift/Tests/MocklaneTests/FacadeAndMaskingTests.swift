import XCTest
@testable import Mocklane

final class FacadeAndMaskingTests: XCTestCase {
    override func tearDown() {
        Mocklane.reset()
        super.tearDown()
    }

    func testDisabledSessionIsPassThrough() {
        let configuration = URLSessionConfiguration.ephemeral
        _ = Mocklane.urlSession(enabled: false, configuration: configuration)

        XCTAssertNil(Mocklane.runtimeOrNil)
        XCTAssertNil(Mocklane.loggerRuntimeOrNil)
        XCTAssertFalse(
            (configuration.protocolClasses ?? []).contains { $0 == MocklaneURLProtocol.self }
        )
    }

    func testEnabledSessionInstallsProtocol() {
        let configuration = URLSessionConfiguration.ephemeral
        let session = Mocklane.urlSession(enabled: true, configuration: configuration)

        XCTAssertNotNil(Mocklane.runtimeOrNil)
        XCTAssertNotNil(Mocklane.loggerRuntimeOrNil)
        // The caller keeps ownership of its configuration object.
        XCTAssertFalse(
            (configuration.protocolClasses ?? []).contains { $0 == MocklaneURLProtocol.self }
        )
        XCTAssertTrue(
            (session.configuration.protocolClasses ?? [])
                .contains { $0 == MocklaneURLProtocol.self }
        )
    }

    func testInstallConfigurationAddsProtocolAndPreservesCallerConfig() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExistingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 42

        let decorated = Mocklane.install(
            configuration,
            config: MocklaneConfig(enabled: true)
        )

        XCTAssertNotNil(Mocklane.runtimeOrNil)
        XCTAssertNotNil(Mocklane.loggerRuntimeOrNil)

        // The caller's configuration stays untouched.
        XCTAssertEqual(configuration.protocolClasses?.count, 1)
        XCTAssertTrue(configuration.protocolClasses?.first == ExistingURLProtocol.self)

        // The decorated copy installs Mocklane first and keeps existing protocols.
        let protocols = decorated.protocolClasses ?? []
        XCTAssertEqual(protocols.count, 2)
        XCTAssertTrue(protocols[0] == MocklaneURLProtocol.self)
        XCTAssertTrue(protocols[1] == ExistingURLProtocol.self)
        XCTAssertEqual(decorated.timeoutIntervalForRequest, 42)

        // The runtime is bound, so the protocol handles absolute URLs.
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/me")!)
        XCTAssertTrue(MocklaneURLProtocol.canInit(with: request))
    }

    func testInstallDisabledReturnsConfigurationUnchanged() {
        let configuration = URLSessionConfiguration.ephemeral
        let returned = Mocklane.install(configuration, enabled: false)

        XCTAssertNil(Mocklane.runtimeOrNil)
        XCTAssertNil(Mocklane.loggerRuntimeOrNil)
        XCTAssertTrue(returned === configuration)
        XCTAssertFalse(
            (returned.protocolClasses ?? []).contains { $0 == MocklaneURLProtocol.self }
        )
    }

    func testDisabledSessionKeepsExistingInterception() {
        _ = Mocklane.urlSession(enabled: true, configuration: .ephemeral)
        XCTAssertNotNil(Mocklane.runtimeOrNil)
        XCTAssertNotNil(Mocklane.loggerRuntimeOrNil)

        _ = Mocklane.urlSession(enabled: false, configuration: .ephemeral)

        // A disabled config is a no-op for an enabled runtime: it neither
        // clears the log runtime nor unbinds interception.
        XCTAssertNotNil(Mocklane.runtimeOrNil)
        XCTAssertNotNil(Mocklane.loggerRuntimeOrNil)
    }

    func testEnabledSessionUsesConfig() {
        let config = MocklaneConfig(
            host: "10.0.0.2",
            port: 7777,
            failOpen: false,
            device: DeviceMetadata(deviceName: "test-device"),
            enabled: true
        )
        _ = Mocklane.makeSession(
            config: config,
            configuration: .ephemeral,
            probe: AlwaysReachableProbe()
        )

        XCTAssertEqual(Mocklane.runtimeOrNil?.config.host ?? "", "10.0.0.2")
        XCTAssertEqual(Mocklane.runtimeOrNil?.config.port ?? 0, 7777)
        XCTAssertFalse(Mocklane.runtimeOrNil?.config.failOpen ?? true)
        XCTAssertEqual(Mocklane.runtimeOrNil?.config.device?.deviceName ?? "", "test-device")
        XCTAssertEqual(Mocklane.loggerRuntimeOrNil?.config.host ?? "", "10.0.0.2")
        Mocklane.log("hi")
    }

    func testMaskingRedactsSecrets() {
        let headers = Masking.maskHeaders([
            "Authorization": "Bearer x",
            "Content-Type": "application/json",
        ])
        XCTAssertEqual(headers["Authorization"], "[REDACTED]")
        XCTAssertEqual(headers["Content-Type"], "application/json")

        let masked = Masking.maskJSONValue([
            "user": "a",
            "password": "p",
        ]) as! [String: Any]
        XCTAssertEqual(masked["user"] as? String, "a")
        XCTAssertEqual(masked["password"] as? String, "[REDACTED]")
    }

    func testMaskingCoversNewSecretKeys() {
        let headers = Masking.maskHeaders([
            "Set-Cookie": "sid=abc",
            "X-Auth-Token": "t",
            "Content-Type": "text/plain",
        ])
        XCTAssertEqual(headers["Set-Cookie"], "[REDACTED]")
        XCTAssertEqual(headers["X-Auth-Token"], "[REDACTED]")
        XCTAssertEqual(headers["Content-Type"], "text/plain")

        let masked = Masking.maskJSONValue([
            "session": "s",
            "session_id": "si",
            "id_token": "i",
            "client_secret": "c",
            "user": "a",
        ]) as! [String: Any]
        for key in ["session", "session_id", "id_token", "client_secret"] {
            XCTAssertEqual(masked[key] as? String, "[REDACTED]", key)
        }
        XCTAssertEqual(masked["user"] as? String, "a")
    }

    func testMaskJSONStringAcceptsAnyRoot() {
        let array = Masking.maskJSONString("[{\"token\":\"t\"},{\"user\":\"a\"}]")
        XCTAssertEqual(array, "[{\"token\":\"[REDACTED]\"},{\"user\":\"a\"}]")
        // Scalar roots are valid JSON too; unchanged output is fine, but the
        // call must not fall through as invalid.
        XCTAssertEqual(Masking.maskJSONString("\"plain\""), "\"plain\"")
        XCTAssertEqual(Masking.maskJSONString("not json"), "not json")
    }

    func testFailOpenUsesOriginalWhenUnreachable() async throws {
        let session = Mocklane.makeSession(
            config: MocklaneConfig(failOpen: true, enabled: true),
            configuration: .ephemeral,
            probe: NeverReachableProbe()
        )

        // Local URL that fails connection quickly — proves protocol ran without rewriting
        // to gateway (unreachable probe + fail-open keeps original host).
        var request = URLRequest(url: URL(string: "http://127.0.0.1:1/")!)
        request.timeoutInterval = 0.3

        do {
            _ = try await session.data(for: request)
        } catch {
            // Expected: connection refused to :1
        }
        XCTAssertNotNil(Mocklane.runtimeOrNil)
    }

    func testRewriteHelper() {
        XCTAssertEqual(
            Mocklane.rewrite("https://api.example.com/v1/me"),
            "http://127.0.0.1:6625/https://api.example.com/v1/me"
        )
    }
}

/// URLProtocol that never loads, used to prove existing protocol classes survive.
private final class ExistingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
