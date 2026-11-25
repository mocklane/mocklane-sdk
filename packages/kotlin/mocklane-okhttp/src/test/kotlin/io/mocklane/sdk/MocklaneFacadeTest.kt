@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

class MocklaneFacadeTest {
    @Test
    fun interceptorUsesConfigForGatewayAndDevice() {
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
            val client =
                OkHttpClient.Builder()
                    .addInterceptor(MocklaneOkHttp.interceptor(config))
                    .build()

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
    fun disabledBooleanInterceptorIsPassThrough() {
        val upstream = MockWebServer()
        upstream.enqueue(MockResponse().setBody("direct"))
        upstream.start()

        try {
            val client =
                OkHttpClient.Builder()
                    .addInterceptor(MocklaneOkHttp.interceptor(enabled = false))
                    .build()

            val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
            client.newCall(Request.Builder().url(target).build()).execute().use {
                assertEquals(200, it.code)
                assertEquals("direct", it.body?.string())
            }

            val recorded = upstream.takeRequest()
            assertEquals("/v1/me", recorded.path)
            assertEquals(null, recorded.getHeader("X-Mocklane-Device-Name"))
        } finally {
            upstream.shutdown()
        }
    }

    @Test
    fun logUsesInterceptorConfig() {
        val gateway = MockWebServer()
        gateway.start()

        try {
            MocklaneOkHttp.interceptor(
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
    fun disabledInterceptorKeepsRuntimeOfEnabledAdapter() {
        val gateway = MockWebServer()
        gateway.start()

        try {
            MocklaneOkHttp.interceptor(
                MocklaneConfig(
                    host = gateway.hostName,
                    port = gateway.port,
                    device = DeviceMetadata(deviceName = "facade-multi"),
                    enabled = true,
                ),
            )
            MocklaneOkHttp.interceptor(MocklaneConfig(enabled = false))
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
            val client =
                OkHttpClient.Builder()
                    .addInterceptor(MocklaneOkHttp.interceptor(config))
                    .build()

            val target = "http://${upstream.hostName}:${upstream.port}/v1/me"
            client.newCall(Request.Builder().url(target).build()).execute().use {
                assertEquals(200, it.code)
                assertEquals("direct", it.body?.string())
            }

            val recorded = upstream.takeRequest()
            assertEquals("/v1/me", recorded.path)
            assertEquals(null, recorded.getHeader("X-Mocklane-Device-Name"))
        } finally {
            upstream.shutdown()
        }
    }
}
