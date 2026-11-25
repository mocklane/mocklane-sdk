@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.AlwaysReachableProbe
import io.mocklane.sdk.internal.MocklaneOkHttpInterceptor
import io.mocklane.sdk.internal.NeverReachableProbe
import kotlin.test.Test
import kotlin.test.assertEquals
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class OkHttpInterceptorTest {
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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, AlwaysReachableProbe))
                .build()

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val response = client.newCall(Request.Builder().url(target).build()).execute()
        assertEquals(200, response.code)

        val recorded = gateway.takeRequest()
        assertEquals(
            "/http://${upstream.hostName}:${upstream.port}/v1/me",
            recorded.path,
        )
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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, NeverReachableProbe))
                .build()

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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, NeverReachableProbe))
                .build()

        val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
        val response = client.newCall(Request.Builder().url(target).build()).execute()
        response.use {
            assertEquals(200, it.code)
            assertEquals("direct", it.body?.string())
        }

        val recorded = upstream.takeRequest()
        assertEquals("/v1/me", recorded.path)
        assertEquals(null, recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
    }

    @Test
    fun skipsWebSocketHandshakeWhenGatewayIsDown() {
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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, NeverReachableProbe))
                .build()

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
        assertEquals(null, recorded.getHeader("X-Mocklane-Device-Name"))

        upstream.shutdown()
    }

    @Test
    fun skipsGrpcWhenGatewayIsDown() {
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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, NeverReachableProbe))
                .build()

        val target = "http://${upstream.hostName}:${upstream.port}/pkg.Service/Method"
        val body = byteArrayOf(0, 0, 0, 0, 0).toRequestBody("application/grpc+proto".toMediaType())
        val request = Request.Builder().url(target).post(body).build()

        client.newCall(request).execute().use { response ->
            assertEquals(200, response.code)
        }

        val recorded = upstream.takeRequest()
        assertEquals("/pkg.Service/Method", recorded.path)
        assertEquals("application/grpc+proto", recorded.getHeader("Content-Type"))
        assertEquals(null, recorded.getHeader("X-Mocklane-Device-Name"))

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
        val client =
            OkHttpClient.Builder()
                .addInterceptor(MocklaneOkHttpInterceptor(config, AlwaysReachableProbe))
                .build()

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
}
