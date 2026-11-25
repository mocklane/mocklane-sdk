import XCTest
@testable import Mocklane

final class RewriteTests: XCTestCase {
    func testCorpusCases() throws {
        let url = Bundle.module.url(forResource: "url-rewrite", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let cases = try JSONDecoder().decode([CorpusCase].self, from: data)
        for c in cases {
            let got = MocklaneRewrite.rewriteToGateway(
                c.input,
                host: c.gatewayHost,
                port: c.port
            )
            XCTAssertEqual(got, c.expected, c.id)
        }
    }

    func testNoDoublePrefix() {
        let already = "http://127.0.0.1:6625/https://api.example.com/v1"
        XCTAssertEqual(MocklaneRewrite.rewriteToGateway(already), already)
    }

    func testRelativeUnchanged() {
        XCTAssertEqual(MocklaneRewrite.rewriteToGateway("/v1/me"), "/v1/me")
    }

    func testGatewayURLUsesSchemeDefaultPort() {
        XCTAssertTrue(
            MocklaneRewrite.isGatewayURL("http://127.0.0.1/", host: "127.0.0.1", port: 80)
        )
        XCTAssertTrue(
            MocklaneRewrite.isGatewayURL("https://127.0.0.1/", host: "127.0.0.1", port: 443)
        )
        XCTAssertFalse(
            MocklaneRewrite.isGatewayURL("http://127.0.0.1/", host: "127.0.0.1", port: 6625)
        )
    }
}

private struct CorpusCase: Decodable {
    let id: String
    let input: String
    let gatewayHost: String
    let port: Int
    let expected: String
}
