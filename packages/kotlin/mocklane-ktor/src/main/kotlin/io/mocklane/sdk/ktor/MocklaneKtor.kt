@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.ktor

import io.ktor.client.plugins.api.ClientPlugin
import io.ktor.client.plugins.api.createClientPlugin
import io.ktor.http.HttpHeaders
import io.ktor.http.content.OutgoingContent
import io.ktor.http.isWebsocket
import io.ktor.http.takeFrom
import io.mocklane.sdk.Mocklane
import io.mocklane.sdk.MocklaneInternalApi
import io.mocklane.sdk.internal.DeviceHeaders
import io.mocklane.sdk.internal.GatewayProbe
import io.mocklane.sdk.internal.HttpGatewayProbe
import io.mocklane.sdk.internal.Rewrite
import io.mocklane.sdk.internal.UnsupportedProtocols
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Ktor client plugin for Mocklane.
 *
 * Engine-agnostic: works with CIO, OkHttp, Android, Darwin, and MockEngine.
 * Install it on the `HttpClient` you use for API calls:
 *
 * ```kotlin
 * val client = HttpClient {
 *     install(MocklaneKtor) {
 *         config = MocklaneConfig(enabled = BuildConfig.DEBUG)
 *     }
 * }
 * ```
 *
 * The plugin rewrites absolute http(s) requests to the loopback gateway and
 * adds device labels. Handshakes and gRPC bodies are passed through untouched.
 */
public val MocklaneKtor: ClientPlugin<MocklaneKtorConfig> =
    createClientPlugin("MocklaneKtor", ::MocklaneKtorConfig) {
        val resolved = Mocklane.bind(pluginConfig.config)
        val probe: GatewayProbe = HttpGatewayProbe(resolved)

        onRequest { request, content ->
            if (!resolved.enabled) return@onRequest
            if (request.url.host.isEmpty()) return@onRequest

            val original = request.url.buildString()
            val contentType =
                request.headers[HttpHeaders.ContentType]
                    ?: (request.body as? OutgoingContent)?.contentType?.toString()
                    ?: (content as? OutgoingContent)?.contentType?.toString()
            // Ktor controls the Upgrade/Connection headers in the engine, so a
            // WebSocket handshake exposes no header the plugin can read. The
            // WebSockets plugin only accepts ws:// / wss:// URLs, so the
            // protocol identifies them.
            val upgrades =
                request.headers.getAll(HttpHeaders.Upgrade).orEmpty() +
                    request.headers.getAll(HttpHeaders.Connection).orEmpty()
            if (request.url.protocol.isWebsocket() ||
                UnsupportedProtocols.shouldSkip(upgrades, contentType)
            ) {
                return@onRequest
            }

            val gateway = Rewrite.toGateway(original, resolved.host, resolved.port)
            if (gateway == original) return@onRequest

            val reachable = withContext(Dispatchers.IO) { probe.isReachable() }
            if (!reachable) {
                if (resolved.failOpen) return@onRequest
                throw IOException(
                    "Mocklane gateway unreachable at ${resolved.host}:${resolved.port}",
                )
            }

            // URLBuilder.takeFrom appends query parameters to the existing
            // builder, so clear them or every parameter is duplicated.
            request.url.parameters.clear()
            request.url.takeFrom(gateway)
            DeviceHeaders.values(resolved.device).forEach { (name, value) ->
                request.headers.remove(name)
                request.headers.append(name, value)
            }
        }
    }
