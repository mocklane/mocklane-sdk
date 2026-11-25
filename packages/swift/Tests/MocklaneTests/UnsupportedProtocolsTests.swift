import XCTest
@testable import Mocklane

final class UnsupportedProtocolsTests: XCTestCase {
    func testSkipsWebSocketHandshake() {
        var request = URLRequest(url: URL(string: "https://api.example.com/socket")!)
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        XCTAssertTrue(UnsupportedProtocols.shouldSkip(request))
    }

    func testSkipsGrpc() {
        var request = URLRequest(url: URL(string: "https://api.example.com/pkg.Service/Method")!)
        request.setValue("application/grpc+proto", forHTTPHeaderField: "Content-Type")
        XCTAssertTrue(UnsupportedProtocols.shouldSkip(request))
    }

    func testAllowsOrdinaryHttp() {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/me")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        XCTAssertFalse(UnsupportedProtocols.shouldSkip(request))
    }
}
