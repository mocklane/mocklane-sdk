@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.internal

import io.mocklane.sdk.MocklaneConfig
import io.mocklane.sdk.MocklaneInternalApi
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * OkHttp network interceptor: keep the client's [CookieJar] keyed to the real
 * origin instead of the gateway host.
 *
 * `BridgeInterceptor` sees only the rewritten gateway URL, so it would load
 * origin cookies from (and store `Set-Cookie` under) `127.0.0.1:6625`. Cookies
 * stored that way are replayed to every origin and a `Set-Cookie` with a
 * `Domain` attribute would be dropped. Because Bridge parses cookies against
 * the URL it sees, this interceptor handles the raw headers on both sides of
 * each gateway-prefixed hop:
 *
 * - request: load the origin's cookies into `Cookie` unless the caller set it;
 * - response: parse `Set-Cookie` against the origin, save it to the jar, and
 *   strip it so Bridge cannot store it under the gateway host.
 *
 * Non-gateway requests (cross-origin redirect targets) pass through untouched,
 * so OkHttp's own cookie scoping and Authorization stripping apply.
 */
internal class MocklaneCookieInterceptor(
    private val config: MocklaneConfig,
    private val cookieJar: CookieJar?,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val jar = cookieJar ?: return chain.proceed(chain.request())
        val request = chain.request()
        val origin = originOf(request.url) ?: return chain.proceed(request)

        val outgoing = withCookie(request, jar, origin)
        val response = chain.proceed(outgoing)

        if (response.headers.values("Set-Cookie").isEmpty()) return response
        val cookies = Cookie.parseAll(origin, response.headers)
        if (cookies.isNotEmpty()) {
            jar.saveFromResponse(origin, cookies)
        }
        return response.newBuilder().removeHeader("Set-Cookie").build()
    }

    private fun withCookie(
        request: Request,
        jar: CookieJar,
        origin: HttpUrl,
    ): Request {
        if (request.header("Cookie") != null) return request
        val cookies = jar.loadForRequest(origin)
        if (cookies.isEmpty()) return request
        val header = cookies.joinToString("; ") { "${it.name}=${it.value}" }
        return request.newBuilder().header("Cookie", header).build()
    }

    /** The embedded origin of a gateway-prefixed request, if any. */
    private fun originOf(url: HttpUrl): HttpUrl? =
        Rewrite.originalFromGateway(url.toString(), config.host, config.port)?.toHttpUrlOrNull()
}
