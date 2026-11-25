package io.mocklane.sdk.internal

import com.sun.net.httpserver.HttpServer
import io.mocklane.sdk.DeviceMetadata
import io.mocklane.sdk.LogLevel
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LoggerTest {
    private class FailingTransport : LoggerTransport {
        override fun send(message: String, level: LogLevel, tag: String?) {
            error("boom")
        }
    }

    @Test
    fun logNeverThrowsWhenTransportFails() {
        Logger(FailingTransport()).log("hello")
    }

    @Test
    fun logForwardsMessageLevelAndTag() {
        var captured: Triple<String, LogLevel, String?>? = null
        Logger { m, l, t -> captured = Triple(m, l, t) }.log("hi", LogLevel.WARN, "home")
        assertEquals(Triple("hi", LogLevel.WARN, "home"), captured)
    }

    @Test
    fun httpTransportPostsStructuredJsonWithDeviceHeaders() {
        val received = CountDownLatch(1)
        val capturedBody = mutableListOf<String>()
        val capturedDeviceName = mutableListOf<String>()
        val capturedDeviceId = mutableListOf<String>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/__mocklane/v1/log") { exchange ->
            capturedBody += exchange.requestBody.readBytes().decodeToString()
            capturedDeviceName += exchange.requestHeaders.getFirst("X-Mocklane-Device-Name") ?: ""
            capturedDeviceId += exchange.requestHeaders.getFirst("X-Mocklane-Device-Id") ?: ""
            exchange.sendResponseHeaders(200, -1)
            exchange.close()
            received.countDown()
        }
        server.start()

        val executor: ExecutorService = Executors.newSingleThreadExecutor()
        try {
            val device = DeviceMetadata(deviceId = "kotlin-test", deviceName = "log-test")
            val transport =
                HttpLoggerTransport(
                    host = "127.0.0.1",
                    port = server.address.port,
                    device = device,
                    executor = executor,
                )

            transport.send("say \"hi\"\nnext", LogLevel.INFO, "home")

            assertTrue(received.await(5, TimeUnit.SECONDS), "gateway never received the log POST")

            val body = capturedBody.single()
            assertTrue(body.contains("\"message\":\"say \\\"hi\\\"\\nnext\""), body)
            assertTrue(body.contains("\"level\":\"info\""), body)
            assertTrue(body.contains("\"tag\":\"home\""), body)
            assertTrue(body.contains("\"deviceId\":\"kotlin-test\""), body)
            assertTrue(body.contains("\"deviceName\":\"log-test\""), body)
            assertEquals("log-test", capturedDeviceName.single())
            assertEquals("kotlin-test", capturedDeviceId.single())
        } finally {
            executor.shutdownNow()
            server.stop(0)
        }
    }
}
