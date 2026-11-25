import XCTest
@testable import Mocklane

final class MocklaneConfigTests: XCTestCase {
    func testDefaults() {
        let config = MocklaneConfig(enabled: false)
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertEqual(config.port, 6625)
        XCTAssertTrue(config.failOpen)
        XCTAssertEqual(config.probeTimeoutMs, 150)
        XCTAssertNil(config.device)
        XCTAssertFalse(config.enabled)
    }

    func testTrimsHost() {
        let config = MocklaneConfig(host: " 127.0.0.1\n", enabled: false)
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertEqual(config.gatewayBaseURL.absoluteString, "http://127.0.0.1:6625")
    }

    func testWithPlatformDefaultsFillsDevice() {
        let resolved = MocklaneConfig(enabled: true).withPlatformDefaults()
        XCTAssertNotNil(resolved.device)
        XCTAssertFalse(resolved.device?.deviceName?.isEmpty ?? true)
    }

    func testWithPlatformDefaultsKeepsExplicitDevice() {
        let device = DeviceMetadata(deviceId: "id", deviceName: "name", os: "os")
        let resolved = MocklaneConfig(device: device, enabled: true).withPlatformDefaults()
        XCTAssertEqual(resolved.device, device)
    }

    func testBlankHostFallsBackAndDisables() {
        let config = MocklaneConfig(host: "  \n", enabled: true)
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertFalse(config.enabled)
        XCTAssertNotNil(config.validationError)
        XCTAssertEqual(config.gatewayBaseURL.absoluteString, "http://127.0.0.1:6625")
    }

    func testInvalidPortFallsBackAndDisables() {
        let config = MocklaneConfig(port: 0, enabled: true)
        XCTAssertEqual(config.port, 6625)
        XCTAssertFalse(config.enabled)
        XCTAssertNotNil(config.validationError)
        XCTAssertEqual(config.healthURL.absoluteString, "http://127.0.0.1:6625/__mocklane/v1/health")
    }

    func testInvalidProbeTimeoutFallsBackWithoutDisabling() {
        let config = MocklaneConfig(probeTimeoutMs: 0, enabled: true)
        XCTAssertEqual(config.probeTimeoutMs, 150)
        XCTAssertTrue(config.enabled)
        XCTAssertNotNil(config.validationError)
    }

    func testBareIPv6HostIsBracketed() {
        let config = MocklaneConfig(host: "::1", enabled: true)
        XCTAssertEqual(config.host, "[::1]")
        XCTAssertNil(config.validationError)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.gatewayBaseURL.absoluteString, "http://[::1]:6625")
    }

    func testHostWithPathIsRejected() {
        let config = MocklaneConfig(host: "api.example.com/evil", enabled: true)
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertFalse(config.enabled)
        XCTAssertNotNil(config.validationError)
    }

    func testWithPlatformDefaultsCarriesValidationError() {
        let resolved = MocklaneConfig(port: -1, enabled: true).withPlatformDefaults()
        XCTAssertEqual(resolved.port, 6625)
        XCTAssertFalse(resolved.enabled)
        XCTAssertNotNil(resolved.validationError)
    }
}
