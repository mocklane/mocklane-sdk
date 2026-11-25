package io.mocklane.sdk.ktor

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.HttpHeaders
import io.mocklane.sdk.DeviceMetadata
import io.mocklane.sdk.MocklaneConfig
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlinx.coroutines.runBlocking

class MocklaneKtorTest {
    private lateinit var gateway: HealthGateway

    @BeforeTest
    fun startGateway() {
        gateway = HealthGateway()
    }

    @AfterTest
    fun stopGateway() {
        gateway.close()
    }

    @Test
    fun rewritesAbsoluteUrlAndAddsDeviceHeaders() {
        runBlocking {
            val engine = MockEngine { respond("ok") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config =
                            MocklaneConfig(
                                host = "127.0.0.1",
                                port = gateway.port,
                                failOpen = false,
                                device = DeviceMetadata(deviceName = "ktor-test"),
                                enabled = true,
                            )
                    }
                }

            try {
                client.get("https://api.example.com/v1/me")

                val recorded = engine.requestHistory.single()
                assertEquals(
                    "http://127.0.0.1:${gateway.port}/https://api.example.com/v1/me",
                    recorded.url.toString(),
                )
                assertEquals("ktor-test", recorded.headers["X-Mocklane-Device-Name"])
                assertNotNull(recorded.headers["X-Mocklane-Device-Id"])
            } finally {
                client.close()
            }
        }
    }

    @Test
    fun preservesPathAndQuery() {
        runBlocking {
            val engine = MockEngine { respond("ok") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config =
                            MocklaneConfig(
                                host = "127.0.0.1",
                                port = gateway.port,
                                failOpen = false,
                                enabled = true,
                            )
                    }
                }

            try {
                client.get("https://api.example.com/v1/items?page=2&sort=name")

                val recorded = engine.requestHistory.single()
                assertEquals(
                    "http://127.0.0.1:${gateway.port}/https://api.example.com/v1/items?page=2&sort=name",
                    recorded.url.toString(),
                )
            } finally {
                client.close()
            }
        }
    }

    @Test
    fun passesThroughWhenDisabled() =
        runBlocking {
            val engine = MockEngine { respond("ok") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config = MocklaneConfig(enabled = false)
                    }
                }

            try {
                client.get("https://api.example.com/v1/me")

                val recorded = engine.requestHistory.single()
                assertEquals("https://api.example.com/v1/me", recorded.url.toString())
                assertEquals(null, recorded.headers["X-Mocklane-Device-Name"])
            } finally {
                client.close()
            }
        }

    @Test
    fun skipsGrpcRequests() =
        runBlocking {
            val engine = MockEngine { respond("grpc") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config =
                            MocklaneConfig(
                                host = "127.0.0.1",
                                port = gateway.port,
                                failOpen = false,
                                enabled = true,
                            )
                    }
                }

            try {
                client.post("https://api.example.com/pkg.Service/Method") {
                    header(HttpHeaders.ContentType, "application/grpc+proto")
                    setBody(byteArrayOf(0, 0, 0, 0, 0))
                }

                val recorded = engine.requestHistory.single()
                assertEquals(
                    "https://api.example.com/pkg.Service/Method",
                    recorded.url.toString(),
                )
            } finally {
                client.close()
            }
        }

    @Test
    fun skipsWebSocketHandshake() {
        runBlocking {
            val engine = MockEngine { respond("handshake") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config =
                            MocklaneConfig(
                                host = "127.0.0.1",
                                port = gateway.port,
                                failOpen = false,
                                enabled = true,
                            )
                    }
                }

            try {
                client.get("wss://api.example.com/socket")

                val recorded = engine.requestHistory.single()
                assertEquals("wss://api.example.com/socket", recorded.url.toString())
            } finally {
                client.close()
            }
        }
    }

    @Test
    fun throwsWhenGatewayIsDownAndFailClosed() =
        runBlocking {
            gateway.close()
            val engine = MockEngine { respond("ok") }
            val client =
                HttpClient(engine) {
                    install(MocklaneKtor) {
                        config =
                            MocklaneConfig(
                                host = "127.0.0.1",
                                port = gateway.port,
                                failOpen = false,
                                enabled = true,
                            )
                    }
                }

            try {
                assertFailsWith<IOException> {
                    client.get("https://api.example.com/v1/me")
                }
                assertEquals(0, engine.requestHistory.size)
            } finally {
                client.close()
            }
        }
}

/** Minimal loopback HTTP server that answers every request with `200 ok`. */
private class HealthGateway : AutoCloseable {
    private val server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
    val port: Int get() = server.localPort

    private val worker =
        Thread {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                socket.use {
                    runCatching {
                        it.soTimeout = 1_000
                        val reader = it.getInputStream().bufferedReader()
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                        }
                        val body = "ok".toByteArray()
                        it.getOutputStream().apply {
                            write(
                                (
                                    "HTTP/1.1 200 OK\r\n" +
                                        "Content-Length: ${body.size}\r\n" +
                                        "Connection: close\r\n\r\n"
                                ).toByteArray(),
                            )
                            write(body)
                            flush()
                        }
                    }
                }
            }
        }.apply {
            isDaemon = true
            start()
        }

    override fun close() {
        server.close()
    }
}
