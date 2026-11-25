import Foundation

/// Entry point for Mocklane.
///
/// Interception is opt-in; pass `enabled` explicitly to `urlSession` or `install`.
public enum Mocklane {
    final class Runtime: @unchecked Sendable {
        let config: MocklaneConfig
        let probe: GatewayProbe
        let logger: Logger
        /// Shared by every intercepted request of this runtime so connection
        /// reuse and streaming survive across requests.
        let forwarder: Forwarder

        init(config: MocklaneConfig, probe: GatewayProbe, logger: Logger, forwarder: Forwarder) {
            self.config = config
            self.probe = probe
            self.logger = logger
            self.forwarder = forwarder
        }
    }

    private static let lock = NSLock()
    private static var runtime: Runtime?
    private static var loggerRuntime: Runtime?

    /// Returns a URLSession with the default gateway settings.
    ///
    /// Shorthand for `urlSession(config: MocklaneConfig(enabled: enabled))`.
    /// For custom settings, pass a `MocklaneConfig`.
    ///
    /// `enabled` is required so release builds cannot enable capture by accident.
    public static func urlSession(
        enabled: Bool,
        configuration: URLSessionConfiguration = .ephemeral,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        urlSession(
            config: MocklaneConfig(enabled: enabled),
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    /// Returns a URLSession with per-client settings.
    ///
    /// This is the full settings overload; the Boolean overload only enables or
    /// disables the default config. Create the session once and reuse it. Set
    /// `enabled = true` to intercept; a disabled config returns a plain session
    /// and leaves the most recent enabled session's `log` runtime untouched.
    ///
    /// The config is also used by `log`. With multiple sessions, the most
    /// recently created enabled session wins.
    public static func urlSession(
        config: MocklaneConfig,
        configuration: URLSessionConfiguration = .ephemeral,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        makeSession(
            config: config,
            configuration: configuration,
            probe: nil,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    /// Installs Mocklane into a copy of `configuration`.
    ///
    /// Use this when the app owns its session factory: decorate the
    /// configuration, then create the session with your own delegate and
    /// delegate queue. The caller's configuration object is not modified, and
    /// existing `protocolClasses` keep working with `MocklaneURLProtocol`
    /// inserted first.
    ///
    /// Interception is opt-in; `enabled = false` returns the configuration
    /// unchanged and leaves an existing enabled session's `log` runtime
    /// untouched. Create the session once and reuse it.
    ///
    /// The default gateway is `127.0.0.1:6625`; pass
    /// `MocklaneConfig(port:enabled:)` to use a different gateway.
    public static func install(
        _ configuration: URLSessionConfiguration,
        config: MocklaneConfig
    ) -> URLSessionConfiguration {
        prepareInterception(
            config: config,
            configuration: configuration,
            probe: nil
        ) ?? configuration
    }

    /// Shorthand for `install(configuration, config: MocklaneConfig(enabled: enabled))`.
    public static func install(
        _ configuration: URLSessionConfiguration,
        enabled: Bool
    ) -> URLSessionConfiguration {
        install(configuration, config: MocklaneConfig(enabled: enabled))
    }

    /// Re-bind the physical-iOS USB mux listen sockets (after unlock / resume).
    /// No-op on Simulator / macOS / when interception is disabled.
    public static func refreshUsbBridge() {
        UsbBridge.ensureListening()
    }

    /// Rewrite an absolute URL to the gateway form.
    public static func rewrite(_ url: String, config: MocklaneConfig? = nil) -> String {
        let resolved = config ?? runtimeOrNil?.config ?? MocklaneConfig(enabled: false)
        return MocklaneRewrite.rewriteToGateway(url, host: resolved.host, port: resolved.port)
    }

    /// Optional structured log to Desktop.
    ///
    /// Uses the config of the most recently created enabled session. No-op when
    /// that session is disabled or none has been created.
    public static func log(_ message: String, level: LogLevel = .info, tag: String? = nil) {
        loggerRuntimeOrNil?.logger.log(message, level: level, tag: tag)
    }

    // MARK: - Internal accessors for URLProtocol

    static func makeSession(
        config: MocklaneConfig,
        configuration: URLSessionConfiguration,
        probe: GatewayProbe?,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        let intercepted =
            prepareInterception(
                config: config,
                configuration: configuration,
                probe: probe
            ) ?? configuration
        return URLSession(
            configuration: intercepted,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    /// Bind the runtime and return a copy of `configuration` with Mocklane's
    /// URLProtocol installed. Returns nil when interception is disabled.
    private static func prepareInterception(
        config: MocklaneConfig,
        configuration: URLSessionConfiguration,
        probe: GatewayProbe?
    ) -> URLSessionConfiguration? {
        // A disabled config is a pure pass-through: it neither clears the log
        // runtime bound by an enabled session nor stops the USB bridge.
        // `Mocklane.reset()` is the teardown entry point.
        guard config.enabled else { return nil }

        // Foreground, in-process sessions only: background sessions reject
        // custom URLProtocol classes, so interception cannot work there.
        precondition(
            configuration.identifier == nil,
            "Mocklane cannot intercept a background URLSessionConfiguration: "
                + "custom URLProtocol classes are not supported by background sessions"
        )

        let resolved = config.withPlatformDefaults()
        let newRuntime = Runtime(
            config: resolved,
            probe: probe ?? HttpGatewayProbe(config: resolved),
            logger: Logger(transport: HttpLoggerTransport(config: resolved)),
            forwarder: Forwarder(configuration: configuration, config: resolved)
        )

        lock.lock()
        let previous = runtime
        runtime = newRuntime
        loggerRuntime = newRuntime
        lock.unlock()
        // Let in-flight requests finish, then release the old connections.
        previous?.forwarder.invalidate()

        UsbBridge.startIfNeeded(config: resolved)

        // Copy so the caller can keep reusing its configuration object.
        let intercepted =
            (configuration.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.ephemeral
        var protocols = intercepted.protocolClasses ?? []
        if !protocols.contains(where: { $0 == MocklaneURLProtocol.self }) {
            protocols.insert(MocklaneURLProtocol.self, at: 0)
        }
        intercepted.protocolClasses = protocols
        return intercepted
    }

    static var runtimeOrNil: Runtime? {
        lock.lock()
        defer { lock.unlock() }
        return runtime
    }

    static var loggerRuntimeOrNil: Runtime? {
        lock.lock()
        defer { lock.unlock() }
        return loggerRuntime
    }

    static func reset() {
        UsbBridge.stop()
        lock.lock()
        let previous = runtime
        runtime = nil
        loggerRuntime = nil
        lock.unlock()
        previous?.forwarder.invalidate()
    }
}
