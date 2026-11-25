package io.mocklane.sdk.internal

import io.mocklane.sdk.MocklaneInternalApi

/**
 * Traffic the gateway cannot forward yet.
 *
 * Adapters pass their client's `Upgrade` header values and effective
 * content type; core stays independent of any HTTP client.
 */
@MocklaneInternalApi
public object UnsupportedProtocols {
    public fun shouldSkip(
        upgradeHeaderValues: List<String>,
        contentType: String?,
    ): Boolean = isWebSocketHandshake(upgradeHeaderValues) || isGrpc(contentType)

    public fun isWebSocketHandshake(upgradeHeaderValues: List<String>): Boolean =
        upgradeHeaderValues.any { value ->
            value.split(',').any { token ->
                token.trim().equals("websocket", ignoreCase = true)
            }
        }

    public fun isGrpc(contentType: String?): Boolean {
        val mediaType = contentType?.substringBefore(';')?.trim() ?: return false
        return mediaType.equals("application/grpc", ignoreCase = true) ||
            mediaType.startsWith("application/grpc+", ignoreCase = true) ||
            mediaType.startsWith("application/grpc-", ignoreCase = true)
    }
}
