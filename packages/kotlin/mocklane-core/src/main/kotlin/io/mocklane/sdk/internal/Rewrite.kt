package io.mocklane.sdk.internal

import io.mocklane.sdk.DEFAULT_GATEWAY_HOST
import io.mocklane.sdk.DEFAULT_GATEWAY_PORT
import io.mocklane.sdk.MocklaneInternalApi
import java.net.URI

/**
 * URL rewrite — matches Desktop `url_map` origin-prefixed form.
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
        return toGateway(uri, host, port)
    }

    fun toGateway(
        input: URI,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): String {
        val scheme = input.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            return input.toString()
        }
        if (isGatewayUrl(input, host, port)) {
            return input.toString()
        }

        val path = if (input.rawPath.isNullOrEmpty()) "/" else input.rawPath
        val query = if (input.rawQuery.isNullOrEmpty()) "" else "?${input.rawQuery}"
        // Fragment stripped (gateway U17). Built as a string rather than a URI:
        // `java.net.URI` rejects '[' and ']' in the path, and an IPv6 origin
        // keeps its brackets in the embedded origin.
        val authority = input.rawAuthority ?: return input.toString()
        return "http://$host:$port/$scheme://$authority$path$query"
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

    /**
     * Unwrap a gateway-prefixed URL back to the request for the embedded
     * origin (`http://host:port/https://api.example.com/x` →
     * `https://api.example.com/x`, query reattached).
     *
     * Returns `null` when [input] is not a gateway URL or the embedded part is
     * not an absolute http(s) URL.
     */
    fun originalFromGateway(
        input: String,
        host: String = DEFAULT_GATEWAY_HOST,
        port: Int = DEFAULT_GATEWAY_PORT,
    ): String? {
        // `URI` cannot represent '[' or ']' in a path segment, which an IPv6
        // origin embeds. Use it when it parses and fall back to the authority
        // prefix for those URLs.
        runCatching { URI(input) }.getOrNull()?.let { uri ->
            if (!isGatewayUrl(uri, host, port)) return null
            val rawPath = uri.rawPath ?: return null
            if (!rawPath.startsWith('/')) return null
            val embedded = rawPath.substring(1) + (uri.rawQuery?.let { "?$it" } ?: "")
            return validateOriginal(embedded)
        }
        val prefix = "http://$host:$port/"
        if (!input.startsWith(prefix, ignoreCase = true)) return null
        return validateOriginal(input.substring(prefix.length))
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

    private fun validateOriginal(embedded: String): String? {
        val original = runCatching { URI(embedded) }.getOrNull() ?: return null
        val scheme = original.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return null
        if (original.host.isNullOrEmpty()) return null
        return embedded
    }
}
