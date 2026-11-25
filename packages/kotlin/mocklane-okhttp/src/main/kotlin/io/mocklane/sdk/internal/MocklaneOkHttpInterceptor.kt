@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.internal

import io.mocklane.sdk.MocklaneConfig
import io.mocklane.sdk.MocklaneInternalApi
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * OkHttp application interceptor: rewrites absolute http(s) requests to the
 * gateway when it is reachable.
 *
 * This must stay an application interceptor. OkHttp picks the connection from
 * the URL as seen by `RetryAndFollowUpInterceptor`
 * (`RealCall.enterNetworkInterceptorExchange`), which runs above
 * `ConnectInterceptor`; a network interceptor cannot change the connection
 * target. Cookie scoping happens in [MocklaneCookieInterceptor], per hop.
 */
internal class MocklaneOkHttpInterceptor(
    private val config: MocklaneConfig,
    private val probe: GatewayProbe,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        if (!config.enabled) {
            return chain.proceed(original)
        }
        if (UnsupportedProtocols.shouldSkip(original.headers.values("Upgrade"), contentType(original))) {
            return chain.proceed(original)
        }

        val uri = original.url.toUri()
        if (!Rewrite.shouldRewrite(uri, config.host, config.port)) {
            return chain.proceed(original)
        }

        if (!probe.isReachable()) {
            if (config.failOpen) {
                return chain.proceed(original)
            }
            throw java.io.IOException(
                "Mocklane gateway unreachable at ${config.host}:${config.port}",
            )
        }

        val gateway = Rewrite.toGateway(uri, config.host, config.port)
        val builder =
            original
                .newBuilder()
                .url(gateway.toString())
                // BridgeInterceptor only sets Host when it is absent; drop a
                // caller-provided one so it describes the gateway URL.
                .removeHeader("Host")
        DeviceHeaders.values(config.device).forEach { (name, value) ->
            builder.header(name, value)
        }
        return chain.proceed(builder.build())
    }

    private fun contentType(request: Request): String? =
        request.body?.contentType()?.toString() ?: request.header("Content-Type")
}
