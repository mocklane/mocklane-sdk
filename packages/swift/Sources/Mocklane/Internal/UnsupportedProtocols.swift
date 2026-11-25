import Foundation

/// Requests the gateway cannot relay yet. Leave them on the original connection
/// instead of rewriting them into a guaranteed failure.
///
/// WebSocket needs an Upgrade tunnel; gRPC (and gRPC-Web) needs HTTP/2 streaming
/// and trailers. Desktop tracks them in #138 and #139.
enum UnsupportedProtocols {
    static func shouldSkip(_ request: URLRequest) -> Bool {
        isWebSocketHandshake(request) || isGrpc(request)
    }

    // RFC 6455 also requires `Connection: Upgrade`; keying off `Upgrade` alone
    // is deliberate. It is the protocol signal, and a false positive only
    // means one request skips capture instead of reaching the gateway.
    private static func isWebSocketHandshake(_ request: URLRequest) -> Bool {
        guard let upgrade = request.value(forHTTPHeaderField: "Upgrade") else { return false }
        return upgrade.split(separator: ",").contains {
            String($0).trimmingCharacters(in: .whitespaces).lowercased() == "websocket"
        }
    }

    private static func isGrpc(_ request: URLRequest) -> Bool {
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type") else {
            return false
        }
        // application/grpc[+proto|+json] and application/grpc-web[-text].
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return mediaType == "application/grpc" ||
            mediaType.hasPrefix("application/grpc+") ||
            mediaType.hasPrefix("application/grpc-")
    }
}
