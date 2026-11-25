@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.internal

import io.mocklane.sdk.MocklaneConfig
import io.mocklane.sdk.MocklaneInternalApi
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/** OkHttp interceptor (SRP): rewrite absolute http(s) when gateway is reachable. */
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
        val builder = original.newBuilder().url(gateway.toString())
        DeviceHeaders.values(config.device).forEach { (name, value) ->
            builder.header(name, value)
        }
        return chain.proceed(builder.build())
    }

    private fun contentType(request: Request): String? =
        request.body?.contentType()?.toString() ?: request.header("Content-Type")
}
