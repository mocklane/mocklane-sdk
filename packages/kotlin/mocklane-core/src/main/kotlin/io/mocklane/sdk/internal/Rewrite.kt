package io.mocklane.sdk.internal

import io.mocklane.sdk.DEFAULT_GATEWAY_HOST
import io.mocklane.sdk.DEFAULT_GATEWAY_PORT
import io.mocklane.sdk.MocklaneInternalApi
import java.net.URI

/**
 * URL rewrite (SRP) — matches Desktop `url_map` origin-prefixed form.
 *
 * `https://api.example.com/v1/x` → `http://127.0.0.1:6625/https://api.example.com/v1/x`
 *
 * Public only so client adapters can share the rewrite; client code should use
 * `Mocklane.rewrite` or the adapter facade.
 */
@MocklaneInternalApi
public object Rewrite {
    fun toGateway(
        input: String,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): String {
        val uri = runCatching { URI(input) }.getOrNull() ?: return input
        return toGateway(uri, host, port).toString()
    }

    fun toGateway(
        input: URI,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): URI {
        val scheme = input.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            return input
        }
        if (isGatewayUrl(input, host, port)) {
            return input
        }

        val path = if (input.rawPath.isNullOrEmpty()) "/" else input.rawPath
        val query = if (input.rawQuery.isNullOrEmpty()) "" else "?${input.rawQuery}"
        // Fragment stripped (gateway U17).
        val authority = input.rawAuthority ?: return input
        val embedded = "$scheme://$authority$path$query"
        return URI("http://$host:$port/$embedded")
    }

    fun isGatewayUrl(
        input: String,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): Boolean =
        runCatching { isGatewayUrl(URI(input), host, port) }.getOrDefault(false)

    fun isGatewayUrl(
        input: URI,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): Boolean {
        if (input.host == null) return false
        val inputPort =
            when {
                input.port != -1 -> input.port
                input.scheme.equals("https", ignoreCase = true) -> 443
                input.scheme.equals("http", ignoreCase = true) -> 80
                else -> -1
            }
        return input.host == host && inputPort == port
    }

    fun shouldRewrite(
        input: URI,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): Boolean {
        val scheme = input.scheme?.lowercase() ?: return false
        if (scheme != "http" && scheme != "https") return false
        if (input.host.isNullOrEmpty()) return false
        return !isGatewayUrl(input, host, port)
    }
}
