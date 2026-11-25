import Foundation

/// URL rewrite — matches Desktop's origin-prefixed gateway form.
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
        return normalizedHost(urlHost) == normalizedHost(host) && urlPort == port
    }

    /// Unwrap a gateway-prefixed URL back to the embedded origin.
    ///
    /// Returns `nil` for anything that is not `http://host:port/<absolute URL>`,
    /// including relative `Location` values. Used when following redirects:
    /// Desktop rewrites same-origin `Location` values to the gateway form, and
    /// same-origin detection has to see the real origin to keep
    /// `Authorization`/`Cookie` on the hop.
    static func originalURL(
        from input: String,
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort
    ) -> String? {
        let prefix = "http://\(host):\(port)/"
        guard input.count > prefix.count,
              input.lowercased().hasPrefix(prefix.lowercased())
        else { return nil }
        let embedded = String(input.dropFirst(prefix.count))
        guard let url = URL(string: embedded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return embedded
    }

    /// `URL.host` drops IPv6 brackets; config hosts may keep them.
    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    }
}
