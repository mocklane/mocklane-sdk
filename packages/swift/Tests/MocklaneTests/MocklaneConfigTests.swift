import XCTest
@testable import Mocklane

final class MocklaneConfigTests: XCTestCase {
    func testDefaults() {
        let config = MocklaneConfig()
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertEqual(config.port, 6625)
        XCTAssertTrue(config.failOpen)
        XCTAssertEqual(config.probeTimeoutMs, 150)
        XCTAssertNil(config.device)
        XCTAssertFalse(config.enabled)
    }

    func testTrimsHost() {
        let config = MocklaneConfig(host: " 127.0.0.1\n")
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
}
