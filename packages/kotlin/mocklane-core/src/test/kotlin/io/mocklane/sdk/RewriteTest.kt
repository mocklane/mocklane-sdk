package io.mocklane.sdk

import io.mocklane.sdk.internal.Rewrite
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(MocklaneInternalApi::class)
class RewriteTest {
    private val cases: List<Map<String, Any>> by lazy {
        val candidates =
            listOf(
                Path.of("../../../fixtures/url-rewrite.json"),
                Path.of("../../fixtures/url-rewrite.json"),
                Path.of("../fixtures/url-rewrite.json"),
            )
        val resolved =
            candidates
                .map { it.toAbsolutePath().normalize() }
                .firstOrNull { Files.exists(it) }
                ?: error("url-rewrite.json not found (looked in $candidates)")
        parseCases(Files.readString(resolved))
    }

    @Test
    fun sharedCases() {
        for (c in cases) {
            val input = c["input"] as String
            val host = c["gatewayHost"] as String
            val port = (c["port"] as Number).toInt()
            val expected = c["expected"] as String
            assertEquals(
                expected,
                Rewrite.toGateway(input, host, port),
                "case ${c["id"]}",
            )
        }
    }

    @Test
    fun leavesRelativeUnchanged() {
        assertEquals("/v1/me", Rewrite.toGateway("/v1/me"))
    }

    @Test
    fun doesNotDoublePrefix() {
        val already = "http://127.0.0.1:6625/https://api.example.com/v1"
        assertEquals(already, Rewrite.toGateway(already))
        assertTrue(Rewrite.isGatewayUrl(already))
        assertFalse(Rewrite.isGatewayUrl("https://api.example.com/v1"))
    }
}

private fun parseCases(text: String): List<Map<String, Any>> {
    val objects = Regex("""\{[^{}]+\}""").findAll(text).map { it.value }.toList()
    return objects.map { obj ->
        fun str(key: String): String =
            Regex(""""$key"\s*:\s*"((?:\\.|[^"\\])*)"""").find(obj)?.groupValues?.get(1)
                ?: error("missing $key in $obj")

        fun num(key: String): Int =
            Regex(""""$key"\s*:\s*(\d+)""").find(obj)?.groupValues?.get(1)?.toInt()
                ?: error("missing $key in $obj")
        mapOf(
            "id" to str("id"),
            "input" to str("input"),
            "gatewayHost" to str("gatewayHost"),
            "port" to num("port"),
            "expected" to str("expected"),
        )
    }
}
