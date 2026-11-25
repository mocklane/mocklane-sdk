import Foundation

/// URL rewrite (SRP) — matches Desktop origin-prefixed gateway form.
enum MocklaneRewrite {
    static func rewriteToGateway(
        _ input: String,
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort
    ) -> String {
        guard var components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return input
        }

        if isGatewayURL(input, host: host, port: port) {
            return input
        }

        components.fragment = nil
        // Match the shared rewrite fixtures: bare origin gets a trailing slash.
        if components.path.isEmpty {
            components.path = "/"
        }
        guard let embedded = components.string else { return input }
        return "http://\(host):\(port)/\(embedded)"
    }

    static func rewriteToGateway(
        _ url: URL,
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort
    ) -> URL {
        let rewritten = rewriteToGateway(url.absoluteString, host: host, port: port)
        return URL(string: rewritten) ?? url
    }

    static func isGatewayURL(
        _ input: String,
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort
    ) -> Bool {
        guard let url = URL(string: input), let urlHost = url.host else { return false }
        let urlPort: Int
        if let explicitPort = url.port {
            urlPort = explicitPort
        } else if url.scheme?.lowercased() == "https" {
            urlPort = 443
        } else if url.scheme?.lowercased() == "http" {
            urlPort = 80
        } else {
            return false
        }
        return urlHost == host && urlPort == port
    }
}
