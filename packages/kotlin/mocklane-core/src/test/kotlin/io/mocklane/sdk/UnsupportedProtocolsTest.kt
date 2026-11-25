@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.UnsupportedProtocols
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class UnsupportedProtocolsTest {
    @Test
    fun detectsWebSocketUpgrade() {
        assertTrue(UnsupportedProtocols.isWebSocketHandshake(listOf("WebSocket")))
        assertTrue(UnsupportedProtocols.isWebSocketHandshake(listOf("keep-alive, websocket")))
        assertFalse(UnsupportedProtocols.isWebSocketHandshake(listOf("h2c")))
    }

    @Test
    fun detectsGrpcContentType() {
        assertTrue(UnsupportedProtocols.isGrpc("application/grpc"))
        assertTrue(UnsupportedProtocols.isGrpc("application/grpc+proto"))
        assertTrue(UnsupportedProtocols.isGrpc("application/grpc+proto; charset=utf-8"))
        assertTrue(UnsupportedProtocols.isGrpc("application/grpc-web"))
        assertFalse(UnsupportedProtocols.isGrpc("application/json"))
        assertFalse(UnsupportedProtocols.isGrpc(null))
    }

    @Test
    fun shouldSkipCombinesBothChecks() {
        assertTrue(UnsupportedProtocols.shouldSkip(listOf("websocket"), null))
        assertTrue(UnsupportedProtocols.shouldSkip(emptyList(), "application/grpc+proto"))
        assertFalse(UnsupportedProtocols.shouldSkip(emptyList(), "application/json"))
    }
}
