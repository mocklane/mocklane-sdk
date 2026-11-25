@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.HttpLoggerTransport
import io.mocklane.sdk.internal.Logger
import io.mocklane.sdk.internal.Rewrite

/**
 * Shared Mocklane facade.
 *
 * Interception itself lives in a client adapter ([io.mocklane.sdk.MocklaneOkHttp]
 * or [io.mocklane.sdk.ktor.MocklaneKtor]). This object owns the runtime that
 * [log] and [rewrite] use.
 */
public object Mocklane {
    private class Runtime(
        val config: MocklaneConfig,
        val logger: Logger,
    )

    @Volatile
    private var runtime: Runtime? = null

    /**
     * Optional structured log to Desktop.
     *
     * The message is sent as-is: unlike the JS/Dart/Swift SDKs, Kotlin does not
     * parse JSON or redact fields (the JVM has no built-in JSON parser), so
     * mask secrets before logging.
     *
     * Uses the config of the most recently created **enabled** adapter. A
     * disabled adapter does not change the runtime, so one enabled client keeps
     * logging while other clients stay pass-through. No-op when no adapter has
     * been enabled.
     */
    public fun log(
        message: String,
        level: LogLevel = LogLevel.INFO,
        tag: String? = null,
    ) {
        runtime?.logger?.log(message, level, tag)
    }

    /**
     * Rewrite an absolute http(s) URL to the gateway form.
     *
     * Uses [config] when given, otherwise the config of the most recently
     * created enabled adapter, otherwise the default gateway settings.
     */
    public fun rewrite(url: String, config: MocklaneConfig? = null): String {
        val resolved = config ?: runtime?.config ?: MocklaneConfig()
        return Rewrite.toGateway(url, resolved.host, resolved.port)
    }

    /**
     * Bind the runtime used by [log] and [rewrite] and return the resolved
     * config for the adapter.
     *
     * Adapter implementations call this once per client. Disabling is a no-op
     * so a release build with only disabled clients never binds a runtime.
     */
    @MocklaneInternalApi
    public fun bind(config: MocklaneConfig): MocklaneConfig {
        if (!config.enabled) return config
        val resolved = config.withPlatformDefaults()
        if (runtime?.config == resolved) return resolved
        runtime =
            Runtime(
                config = resolved,
                logger =
                    Logger(
                        HttpLoggerTransport(
                            host = resolved.host,
                            port = resolved.port,
                            device = resolved.device,
                        ),
                    ),
            )
        return resolved
    }

    /** Clear the runtime. Intended for tests and adapter teardown. */
    @MocklaneInternalApi
    public fun reset() {
        runtime = null
    }
}
