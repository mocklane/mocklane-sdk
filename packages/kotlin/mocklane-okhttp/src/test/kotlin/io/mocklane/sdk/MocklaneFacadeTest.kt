@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.MocklaneCookieInterceptor
import io.mocklane.sdk.internal.MocklaneOkHttpInterceptor
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class MocklaneFacadeTest {
    @Test
    fun installUsesConfigForGatewayAndDevice() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("ok"))
        upstream.start()

        val gateway = MockWebServer()
        gateway.enqueue(MockResponse().setBody("healthy"))
        gateway.enqueue(MockResponse().setBody("gw"))
        gateway.start()

        try {
            val config =
                MocklaneConfig(
                    host = gateway.hostName,
                    port = gateway.port,
                    failOpen = false,
                    device = DeviceMetadata(deviceName = "facade-test"),
                    enabled = true,
                )
            val client = MocklaneOkHttp.install(OkHttpClient(), config)

            val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
            client.newCall(Request.Builder().url(target).build()).execute().use {
                assertEquals(200, it.code)
            }

            assertEquals("/__mocklane/v1/health", gateway.takeRequest().path)
            val rewritten = gateway.takeRequest()
            assertEquals(
                "/http://${upstream.hostName}:${upstream.port}/v1/me",
                rewritten.path,
            )
            assertEquals("facade-test", rewritten.getHeader("X-Mocklane-Device-Name"))
            assertNotNull(rewritten.getHeader("X-Mocklane-Device-Id"))
        } finally {
            Mocklane.reset()
            upstream.shutdown()
            gateway.shutdown()
        }
    }

    @Test
    fun installDisabledBooleanIsPassThrough() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        try {
            val client = MocklaneOkHttp.install(OkHttpClient(), enabled = false)

            val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
            client.newCall(Request.Builder().url(target).build()).execute().use {
                assertEquals(200, it.code)
                assertEquals("direct", it.body?.string())
            }

            val recorded = upstream.takeRequest()
            assertEquals("/v1/me", recorded.path)
            assertNull(recorded.getHeader("X-Mocklane-Device-Name"))
        } finally {
            upstream.shutdown()
        }
    }

    @Test
    fun logUsesInstalledConfig() {
        val gateway = MockWebServer()
        gateway.start()

        try {
            MocklaneOkHttp.install(
                OkHttpClient(),
                MocklaneConfig(
                    host = gateway.hostName,
                    port = gateway.port,
                    device = DeviceMetadata(deviceName = "facade-log"),
                    enabled = true,
                ),
            )
            Mocklane.log("hello", tag = "facade")

            val recorded = assertNotNull(gateway.takeRequest(5, TimeUnit.SECONDS))
            assertEquals("/__mocklane/v1/log", recorded.path)
            assertEquals("facade-log", recorded.getHeader("X-Mocklane-Device-Name"))
            assertTrue(recorded.body.readUtf8().contains("\"message\":\"hello\""))
        } finally {
            Mocklane.reset()
            gateway.shutdown()
        }
    }

    @Test
    fun disabledInstallKeepsRuntimeOfEnabledAdapter() {
        val gateway = MockWebServer()
        gateway.start()

        try {
            MocklaneOkHttp.install(
                OkHttpClient(),
                MocklaneConfig(
                    host = gateway.hostName,
                    port = gateway.port,
                    device = DeviceMetadata(deviceName = "facade-multi"),
                    enabled = true,
                ),
            )
            MocklaneOkHttp.install(OkHttpClient(), MocklaneConfig(enabled = false))
            Mocklane.log("still bound", tag = "facade")

            val recorded = assertNotNull(gateway.takeRequest(5, TimeUnit.SECONDS))
            assertEquals("/__mocklane/v1/log", recorded.path)
            assertEquals("facade-multi", recorded.getHeader("X-Mocklane-Device-Name"))
        } finally {
            Mocklane.reset()
            gateway.shutdown()
        }
    }

    @Test
    fun disabledConfigIsPassThrough() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        try {
            val config =
                MocklaneConfig(
                    host = "127.0.0.1",
                    port = 1,
                    failOpen = false,
                    enabled = false,
                )
            val client = MocklaneOkHttp.install(OkHttpClient(), config)

            val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
            client.newCall(Request.Builder().url(target).build()).execute().use {
                assertEquals(200, it.code)
                assertEquals("direct", it.body?.string())
            }

            val recorded = upstream.takeRequest()
            assertEquals("/v1/me", recorded.path)
            assertNull(recorded.getHeader("X-Mocklane-Device-Name"))
        } finally {
            upstream.shutdown()
        }
    }

    @Test
    fun installIsIdempotent() {
        val client = OkHttpClient()
        val installed =
            MocklaneOkHttp.install(
                client,
                MocklaneConfig(host = "127.0.0.1", port = 1, enabled = false),
            )
        val twice = MocklaneOkHttp.install(installed, MocklaneConfig(enabled = true))
        try {
            assertEquals(1, twice.interceptors.count { it is MocklaneOkHttpInterceptor })
            assertEquals(1, twice.networkInterceptors.count { it is MocklaneCookieInterceptor })
        } finally {
            Mocklane.reset()
        }
    }
}
