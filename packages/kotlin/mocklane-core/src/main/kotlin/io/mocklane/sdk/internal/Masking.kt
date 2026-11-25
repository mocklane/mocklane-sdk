package io.mocklane.sdk.internal

internal object Masking {
    private val defaultHeaderKeys =
        setOf("authorization", "cookie", "x-api-key", "proxy-authorization")
    private val defaultJsonKeys =
        setOf("password", "token", "access_token", "refresh_token", "secret", "api_key")

    fun maskHeaders(
        headers: Map<String, String>,
        headerKeys: Set<String> = defaultHeaderKeys,
        replacement: String = "[REDACTED]",
    ): Map<String, String> =
        headers.mapValues { (k, v) ->
            if (headerKeys.contains(k.lowercase())) replacement else v
        }

    @Suppress("UNCHECKED_CAST")
    fun maskJsonValue(
        value: Any?,
        jsonKeys: Set<String> = defaultJsonKeys,
        replacement: String = "[REDACTED]",
    ): Any? =
        when (value) {
            is List<*> -> value.map { maskJsonValue(it, jsonKeys, replacement) }
            is Map<*, *> ->
                value.entries.associate { (k, v) ->
                    val key = k.toString()
                    key to
                        if (jsonKeys.contains(key.lowercase())) {
                            replacement
                        } else {
                            maskJsonValue(v, jsonKeys, replacement)
                        }
                }
            else -> value
        }
}
