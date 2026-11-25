import Foundation

/// Reachability probe (SRP + DIP).
protocol GatewayProbe: Sendable {
    func isReachable() async -> Bool
}

struct AlwaysReachableProbe: GatewayProbe {
    func isReachable() async -> Bool { true }
}

struct NeverReachableProbe: GatewayProbe {
    func isReachable() async -> Bool { false }
}

/// `GET /__mocklane/v1/health` — any HTTP response counts as reachable.
final class HttpGatewayProbe: GatewayProbe, @unchecked Sendable {
    private let config: MocklaneConfig
    private let session: URLSession

    init(config: MocklaneConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let conf = URLSessionConfiguration.ephemeral
            conf.timeoutIntervalForRequest = TimeInterval(config.probeTimeoutMs) / 1000.0
            conf.timeoutIntervalForResource = TimeInterval(config.probeTimeoutMs) / 1000.0
            conf.protocolClasses = [] // never recurse into MocklaneURLProtocol
            self.session = URLSession(configuration: conf)
        }
    }

    func isReachable() async -> Bool {
        var request = URLRequest(url: config.healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(config.probeTimeoutMs) / 1000.0
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
