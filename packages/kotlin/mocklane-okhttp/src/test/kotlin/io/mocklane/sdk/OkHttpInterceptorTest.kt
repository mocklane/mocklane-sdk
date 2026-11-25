@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.AlwaysReachableProbe
import io.mocklane.sdk.internal.GatewayProbe
import io.mocklane.sdk.internal.NeverReachableProbe
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class OkHttpInterceptorTest {
    private fun client(config: MocklaneConfig, probe: GatewayProbe): OkHttpClient =
        MocklaneOkHttp.installWithProbe(OkHttpClient(), config, probe)

    @Test
    fun rewritesWhenGatewayReachable() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("ok"))
        upstream.start()

        // Capture rewritten request host/path via a local "gateway" server.
        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setBody("gw"))
        gateway.start()

        val config =
            MocklaneConfig(
                host = gateway.hostName,
                port = gateway.port,
                failOpen = true,
                device = DeviceMetadata(deviceName = "kotlin-test"),
                enabled = true,
            )
        val client = client(config, AlwaysReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val response = client.newCall(Request.Builder().url(target).build()).execute()
        assertEquals(200, response.code)

        val recorded = gateway.takeRequest()
        assertEquals(
            "/http://${upstream.hostName}:${upstream.port}/v1/me",
            recorded.path,
        )
        assertEquals("${gateway.hostName}:${gateway.port}", recorded.getHeader("Host"))
        assertEquals("kotlin-test", recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
        gateway.shutdown()
    }

    @Test
    fun failOpensWhenGatewayDown() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        val config =
            MocklaneConfig(
                host = "127.0.0.1",
                port = 1,
                failOpen = true,
                enabled = true,
            )
        val client = client(config, NeverReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val response = client.newCall(Request.Builder().url(target).build()).execute()
        assertEquals(200, response.code)
        assertEquals("direct", response.body?.string())
        assertEquals(1, upstream.requestCount)

        upstream.shutdown()
    }

    @Test
    fun passesThroughWhenDisabled() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        val config =
            MocklaneConfig(
                host = "127.0.0.1",
                port = 1,
                failOpen = false,
                enabled = false,
            )
        val client = client(config, NeverReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val response = client.newCall(Request.Builder().url(target).build()).execute()
        response.use {
            assertEquals(200, it.code)
            assertEquals("direct", it.body?.string())
        }

        val recorded = upstream.takeRequest()
        assertEquals("/v1/me", recorded.path)
        assertNull(recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
    }

    @Test
    fun skipsWebSocketHandshake() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("handshake"))
        upstream.start()

        val config =
            MocklaneConfig(
                host = "127.0.0.1",
                port = 1,
                failOpen = false,
                enabled = true,
            )
        val client = client(config, NeverReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/socket"
        val request =
            Request.Builder()
                .url(target)
                .header("Connection", "Upgrade")
                .header("Upgrade", "WebSocket")
                .header("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                .header("Sec-WebSocket-Version", "13")
                .build()

        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
        }

        val recorded = upstream.takeRequest()
        assertEquals("/socket", recorded.path)
        assertNull(recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
    }

    @Test
    fun skipsGrpc() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("grpc"))
        upstream.start()

        val config =
            MocklaneConfig(
                host = "127.0.0.1",
                port = 1,
                failOpen = false,
                enabled = true,
            )
        val client = client(config, NeverReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/pkg.Service/Method"
        val body = byteArrayOf(0, 0, 0, 0, 0).toRequestBody("application/grpc+proto".toMediaType())
        val request = Request.Builder().url(target).post(body).build()

        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
        }

        val recorded = upstream.takeRequest()
        assertEquals("/pkg.Service/Method", recorded.path)
        assertEquals("application/grpc+proto", recorded.getHeader("Content-Type"))
        assertNull(recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
    }

    @Test
    fun rewritesJsonPostWhenGatewayReachable() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("ok"))
        upstream.start()

        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setBody("gw"))
        gateway.start()

        val config =
            MocklaneConfig(
                host = gateway.hostName,
                port = gateway.port,
                failOpen = false,
                device = DeviceMetadata(deviceName = "kotlin-test"),
                enabled = true,
            )
        val client = client(config, AlwaysReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/v1/items"
        val body = """{"name":"one"}""".toRequestBody("application/json".toMediaType())
        val request = Request.Builder().url(target).post(body).build()

        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
        }

        val recorded = gateway.takeRequest()
        assertEquals(
            "/http://${upstream.hostName}:${upstream.port}/v1/items",
            recorded.path,
        )
        assertEquals("kotlin-test", recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
        gateway.shutdown()
    }

    @Test
    fun followsGatewayPrefixedRedirectWithCredentials() {
        // Desktop rewrites same-origin `Location` values to the gateway form,
        // so both hops point at the gateway. OkHttp must follow the second hop
        // through the gateway without double-prefixing it, and keep the
        // caller's Authorization header (the host never changes).
        val gateway = MockWebServer()
        gateway.start()
        gateway.enqueue(
            MockResponse()
                .setResponseCode(302)
                .setHeader(
                    "Location",
                    "http://${gateway.hostName}:${gateway.port}/http://origin.test/final",
                ),
        )
        gateway.enqueue(MockResponse().setBody("gw"))

        val config =
            MocklaneConfig(
                host = gateway.hostName,
                port = gateway.port,
                failOpen = false,
                enabled = true,
            )
        val client = client(config, AlwaysReachableProbe)

        val request =
            Request.Builder()
                .url("http://origin.test/start")
                .header("Authorization", "Bearer t")
                .build()
        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
            assertEquals("gw", response.body?.string())
        }

        val first = gateway.takeRequest()
        assertEquals("/http://origin.test/start", first.path)
        assertEquals("Bearer t", first.getHeader("Authorization"))

        val second = gateway.takeRequest()
        assertEquals("/http://origin.test/final", second.path)
        assertEquals("Bearer t", second.getHeader("Authorization"))

        gateway.shutdown()
    }

    @Test
    fun usesTheCallersCookieHeader() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("ok"))
        upstream.start()

        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setBody("gw"))
        gateway.start()

        val config =
            MocklaneConfig(
                host = gateway.hostName,
                port = gateway.port,
                failOpen = false,
                enabled = true,
            )
        val client = client(config, AlwaysReachableProbe)

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val request =
            Request.Builder()
                .url(target)
                .header("Cookie", "app=1")
                .build()
        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
        }

        assertEquals("app=1", gateway.takeRequest().getHeader("Cookie"))

        upstream.shutdown()
        gateway.shutdown()
    }
}
