import Foundation

/// SDK configuration.
///
/// Pass an instance to `Mocklane.urlSession(config:)`. Interception is opt-in;
/// `enabled` is required, so set it from your build flag.
///
/// Invalid values never trap: the initializer falls back to defaults, records
/// the reason in `validationError`, and leaves interception disabled when the
/// gateway address itself was invalid.
public struct MocklaneConfig: Sendable, Equatable {
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 6625
    public static let defaultProbeTimeoutMs = 150

    public let host: String
    public let port: Int
    /// When `true`, an unreachable gateway falls through to the original request;
    /// when `false`, the request fails.
    public let failOpen: Bool
    /// Fast reachability-probe timeout.
    public let probeTimeoutMs: Int
    /// Device labels for Desktop Traffic. Missing fields are filled from the
    /// platform when the config is resolved.
    public let device: DeviceMetadata?
    /// Enables interception. Required; set it from your build flag. A disabled
    /// config returns a pass-through session and leaves the most recently
    /// enabled session's `Mocklane.log` runtime untouched.
    public let enabled: Bool
    /// Why the initializer substituted a default, if it did. `nil` when every
    /// value was accepted as given.
    public let validationError: String?

    public init(
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort,
        failOpen: Bool = true,
        probeTimeoutMs: Int = MocklaneConfig.defaultProbeTimeoutMs,
        device: DeviceMetadata? = nil,
        enabled: Bool
    ) {
        var problems: [String] = []
        var addressValid = true

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost: String
        if trimmedHost.isEmpty {
            problems.append("host must not be blank")
            resolvedHost = MocklaneConfig.defaultHost
            addressValid = false
        } else if let valid = MocklaneConfig.validHost(trimmedHost) {
            resolvedHost = valid
        } else {
            problems.append("host must form a valid gateway URL, was \"\(host)\"")
            resolvedHost = MocklaneConfig.defaultHost
            addressValid = false
        }

        let resolvedPort: Int
        if (1...65535).contains(port) {
            resolvedPort = port
        } else {
            problems.append("port must be in 1...65535, was \(port)")
            resolvedPort = MocklaneConfig.defaultPort
            addressValid = false
        }

        let resolvedTimeout: Int
        if probeTimeoutMs > 0 {
            resolvedTimeout = probeTimeoutMs
        } else {
            problems.append("probeTimeoutMs must be greater than 0, was \(probeTimeoutMs)")
            resolvedTimeout = MocklaneConfig.defaultProbeTimeoutMs
        }

        self.init(
            sanitizedHost: resolvedHost,
            port: resolvedPort,
            failOpen: failOpen,
            probeTimeoutMs: resolvedTimeout,
            device: device,
            // An invalid address must not leave capture on.
            enabled: addressValid ? enabled : false,
            validationError: problems.isEmpty ? nil : problems.joined(separator: "; ")
        )
    }

    private init(
        sanitizedHost: String,
        port: Int,
        failOpen: Bool,
        probeTimeoutMs: Int,
        device: DeviceMetadata?,
        enabled: Bool,
        validationError: String?
    ) {
        self.host = sanitizedHost
        self.port = port
        self.failOpen = failOpen
        self.probeTimeoutMs = probeTimeoutMs
        self.device = device
        self.enabled = enabled
        self.validationError = validationError
    }

    public var gatewayBaseURL: URL {
        gatewayURL(path: "")
    }

    public var healthURL: URL {
        gatewayURL(path: "/__mocklane/v1/health")
    }

    public var logURL: URL {
        gatewayURL(path: "/__mocklane/v1/log")
    }

    /// Fill missing device labels from the current platform.
    func withPlatformDefaults() -> MocklaneConfig {
        let current = device
        if current?.deviceId != nil && current?.deviceName != nil && current?.os != nil {
            return self
        }
        return MocklaneConfig(
            sanitizedHost: host,
            port: port,
            failOpen: failOpen,
            probeTimeoutMs: probeTimeoutMs,
            device: (current ?? DeviceMetadata()).withPlatformDefaults(),
            enabled: enabled,
            validationError: validationError
        )
    }

    // MARK: - Private

    /// A host string that forms a valid URL authority. Bare IPv6 literals are
    /// bracketed so `::1` and `[::1]` both work.
    private static func validHost(_ trimmed: String) -> String? {
        let candidate = trimmed.contains(":") && !trimmed.hasPrefix("[")
            ? "[\(trimmed)]"
            : trimmed
        guard let url = URL(string: "http://\(candidate):1"),
              let parsed = url.host,
              parsed.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
                  == candidate.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        else { return nil }
        return candidate
    }

    private func gatewayURL(path: String) -> URL {
        URL(string: "http://\(host):\(port)\(path)")
            ?? URL(string: "http://\(MocklaneConfig.defaultHost):\(MocklaneConfig.defaultPort)\(path)")!
    }
}
