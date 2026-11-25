package io.mocklane.sdk

const val DEFAULT_GATEWAY_HOST = "127.0.0.1"
const val DEFAULT_GATEWAY_PORT = 6625
const val DEFAULT_PROBE_TIMEOUT_MS = 150L

/**
 * SDK configuration.
 *
 * Pass an instance to the client adapter (for example
 * `MocklaneOkHttp.interceptor` or `MocklaneKtor`). Interception is opt-in; set
 * [enabled] from your build flag.
 */
data class MocklaneConfig(
    val port: Int = DEFAULT_GATEWAY_PORT,
    val host: String = DEFAULT_GATEWAY_HOST,
    /**
     * When `true`, an unreachable gateway falls through to the original request;
     * when `false`, the interceptor throws.
     */
    val failOpen: Boolean = true,
    /** Fast reachability-probe timeout. */
    val probeTimeoutMs: Long = DEFAULT_PROBE_TIMEOUT_MS,
    /**
     * Device labels for the Desktop Traffic view. Missing fields are filled
     * from the platform when the config is resolved.
     */
    val device: DeviceMetadata? = null,
    /**
     * Enables interception. Defaults to `false`; set it from your build flag.
     * A disabled adapter is a pass-through. It does not clear the runtime of an
     * already enabled adapter, so multiple clients can share one log config.
     */
    val enabled: Boolean = false,
) {
    init {
        require(host.isNotBlank()) { "host must not be blank" }
        require(port in 1..65535) { "port must be in 1..65535, was $port" }
        require(probeTimeoutMs > 0) { "probeTimeoutMs must be greater than 0" }
    }

    /** Fill missing device labels from the current platform. */
    fun withPlatformDefaults(): MocklaneConfig {
        val current = device
        if (current?.deviceId != null && current.deviceName != null && current.os != null) {
            return this
        }
        return copy(device = (current ?: DeviceMetadata()).withPlatformDefaults())
    }
}
