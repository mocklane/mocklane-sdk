import Foundation

/// SDK configuration.
///
/// Pass an instance to `Mocklane.urlSession(config:)`. Interception is opt-in;
/// set `enabled` from your build flag.
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
    /// Enables interception. Defaults to `false`; set it from your build flag.
    /// A disabled config returns a pass-through session and disables
    /// `Mocklane.log`.
    public let enabled: Bool

    public init(
        host: String = MocklaneConfig.defaultHost,
        port: Int = MocklaneConfig.defaultPort,
        failOpen: Bool = true,
        probeTimeoutMs: Int = MocklaneConfig.defaultProbeTimeoutMs,
        device: DeviceMetadata? = nil,
        enabled: Bool = false
    ) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedHost.isEmpty, "host must not be blank")
        precondition((1...65535).contains(port), "port must be in 1...65535, was \(port)")
        precondition(probeTimeoutMs > 0, "probeTimeoutMs must be greater than 0")
        // `gatewayBaseURL` and friends unwrap the URL, so reject hosts that
        // cannot form one (spaces, unbracketed IPv6, …) at construction time.
        precondition(
            URL(string: "http://\(trimmedHost):\(port)") != nil,
            "host must form a valid gateway URL, was \(host)"
        )

        self.host = trimmedHost
        self.port = port
        self.failOpen = failOpen
        self.probeTimeoutMs = probeTimeoutMs
        self.device = device
        self.enabled = enabled
    }

    public var gatewayBaseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public var healthURL: URL {
        URL(string: "http://\(host):\(port)/__mocklane/v1/health")!
    }

    public var logURL: URL {
        URL(string: "http://\(host):\(port)/__mocklane/v1/log")!
    }

    /// Fill missing device labels from the current platform.
    func withPlatformDefaults() -> MocklaneConfig {
        let current = device
        if current?.deviceId != nil && current?.deviceName != nil && current?.os != nil {
            return self
        }
        return MocklaneConfig(
            host: host,
            port: port,
            failOpen: failOpen,
            probeTimeoutMs: probeTimeoutMs,
            device: (current ?? DeviceMetadata()).withPlatformDefaults(),
            enabled: enabled
        )
    }
}
