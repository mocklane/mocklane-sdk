@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.AlwaysReachableProbe
import io.mocklane.sdk.internal.NeverReachableProbe
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class CookieScopingTest {
    private class RecordingJar : CookieJar {
        val saved = mutableListOf<Pair<HttpUrl, List<Cookie>>>()
        private val store = mutableListOf<Cookie>()

        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            saved += url to cookies
            store.removeAll { existing ->
                cookies.any { it.name == existing.name && it.domain == existing.domain }
            }
            store += cookies
        }

        override fun loadForRequest(url: HttpUrl): List<Cookie> =
            store.filter { it.matches(url) }
    }

    private fun install(
        jar: CookieJar,
        gateway: MockWebServer,
        enabled: Boolean = true,
        reachable: Boolean = true,
    ): OkHttpClient {
        val config =
            MocklaneConfig(
                host = gateway.hostName,
                port = gateway.port,
                enabled = enabled,
            )
        val probe = if (reachable) AlwaysReachableProbe else NeverReachableProbe
        return MocklaneOkHttp.installWithProbe(
            OkHttpClient.Builder().cookieJar(jar).build(),
            config,
            probe,
        )
    }

    @Test
    fun setCookieIsStoredUnderTheOriginAndSentBack() {
        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setHeader("Set-Cookie", "sid=abc; Path=/").setBody("ok"))
        gateway.enqueue(MockResponse().setBody("ok"))
        gateway.start()

        val jar = RecordingJar()
        val client = install(jar, gateway)
        val origin = "http://api-a.example.test:8443/login"

        client.newCall(Request.Builder().url(origin).build()).execute().close()
        assertNull(gateway.takeRequest().getHeader("Cookie"))
        assertEquals(origin, jar.saved.single().first.toString())

        client.newCall(Request.Builder().url(origin).build()).execute().close()
        assertEquals("sid=abc", gateway.takeRequest().getHeader("Cookie"))

        // The jar only ever saw the origin, never the gateway authority.
        assertTrue(jar.saved.all { (url, _) -> url.host == "api-a.example.test" })

        gateway.shutdown()
    }

    @Test
    fun cookiesFromOneOriginAreNotSentToAnother() {
        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setBody("a"))
        gateway.enqueue(MockResponse().setBody("b"))
        gateway.start()

        val jar = RecordingJar()
        val originA = "http://api-a.example.test/login".toHttpUrl()
        val originB = "http://api-b.example.test/login".toHttpUrl()
        jar.saveFromResponse(originA, listOf(Cookie.parse(originA, "sid=secret")!!))

        val client = install(jar, gateway)

        client.newCall(Request.Builder().url(originA).build()).execute().close()
        assertEquals("sid=secret", gateway.takeRequest().getHeader("Cookie"))

        client.newCall(Request.Builder().url(originB).build()).execute().close()
        assertNull(gateway.takeRequest().getHeader("Cookie"))

        gateway.shutdown()
    }

    @Test
    fun disabledClientKeepsOkHttpCookieHandling() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        val jar = RecordingJar()
        val origin = "http://${upstream.hostName}:${upstream.port}/v1/me".toHttpUrl()
        jar.saveFromResponse(origin, listOf(Cookie.parse(origin, "sid=direct")!!))

        val client = install(jar, upstream, enabled = false, reachable = false)

        client.newCall(Request.Builder().url(origin).build()).execute().close()
        assertEquals("sid=direct", upstream.takeRequest().getHeader("Cookie"))

        upstream.shutdown()
    }
}
