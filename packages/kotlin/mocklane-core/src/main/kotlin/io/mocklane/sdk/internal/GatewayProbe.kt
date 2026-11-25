package io.mocklane.sdk.internal

import io.mocklane.sdk.MocklaneConfig
import io.mocklane.sdk.MocklaneInternalApi
import java.net.HttpURLConnection
import java.net.URL

/** Reachability probe for the Desktop gateway. */
@MocklaneInternalApi
public fun interface GatewayProbe {
    public fun isReachable(): Boolean
}

/**
 * Loopback health probe built on [HttpURLConnection].
 *
 * Core stays free of client dependencies so every adapter can share the same
 * probe. Any HTTP response means the gateway is up; connection errors mean it is
 * down.
 */
@MocklaneInternalApi
public class HttpGatewayProbe(
    private val host: String,
    private val port: Int,
    private val timeoutMs: Long,
    private val path: String = "/__mocklane/v1/health",
) : GatewayProbe {
    public constructor(config: MocklaneConfig) : this(
        host = config.host,
        port = config.port,
        timeoutMs = config.probeTimeoutMs,
    )

    override fun isReachable(): Boolean =
        runCatching {
            val connection =
                (URL("http://$host:$port$path").openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = timeoutMs.toTimeoutMillis()
                    readTimeout = timeoutMs.toTimeoutMillis()
                    useCaches = false
                }
            try {
                connection.responseCode
                true
            } finally {
                connection.disconnect()
            }
        }.getOrDefault(false)
}

@MocklaneInternalApi
public object AlwaysReachableProbe : GatewayProbe {
    override fun isReachable(): Boolean = true
}

@MocklaneInternalApi
public object NeverReachableProbe : GatewayProbe {
    override fun isReachable(): Boolean = false
}

private fun Long.toTimeoutMillis(): Int =
    coerceAtLeast(1L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
