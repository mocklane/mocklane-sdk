package io.mocklane.sample.demo

import io.mocklane.sample.integration.MocklaneBootstrap
import io.mocklane.sdk.LogLevel
import io.mocklane.sdk.Mocklane
import java.io.IOException
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class DemoResult(
    val id: String,
    val ok: Boolean,
    val status: Int? = null,
    val detail: String,
)

object DemoRunner {
    fun run(scenario: DemoScenario): DemoResult {
        if (!MocklaneBootstrap.isEnabled()) {
            return DemoResult(
                id = scenario.id,
                ok = false,
                detail = "Mocklane disabled in release builds.",
            )
        }

        return when (scenario.kind) {
            "sdk_log" -> runLog(scenario)
            else -> runApi(scenario)
        }
    }

    private fun runLog(scenario: DemoScenario): DemoResult {
        val level =
            when (scenario.logLevel?.lowercase()) {
                "warn" -> LogLevel.WARN
                "error" -> LogLevel.ERROR
                "debug" -> LogLevel.DEBUG
                else -> LogLevel.INFO
            }
        Mocklane.log(scenario.logMessage.orEmpty(), level, scenario.logTag)
        return DemoResult(
            id = scenario.id,
            ok = true,
            detail = "SDK_LOG ${scenario.logLevel} tag=${scenario.logTag}",
        )
    }

    private fun runApi(scenario: DemoScenario): DemoResult {
        val url = scenario.url
            ?: return DemoResult(
                id = scenario.id,
                ok = false,
                detail = "missing url",
            )
        val builder = Request.Builder().url(url)
        scenario.headers.forEach { (k, v) -> builder.header(k, v) }

        val method = scenario.method?.uppercase() ?: "GET"
        if (scenario.body != null) {
            val mediaType = (scenario.contentType ?: "application/json").toMediaType()
            builder.method(method, scenario.body.toRequestBody(mediaType))
        } else {
            builder.method(method, null)
        }

        return try {
            MocklaneBootstrap.client.newCall(builder.build()).execute().use { response ->
                val bodyBytes = response.body?.bytes() ?: byteArrayOf()
                val detail =
                    if (scenario.responseKind == "binary") {
                        "${bodyBytes.size} bytes"
                    } else if (bodyBytes.isEmpty()) {
                        ""
                    } else {
                        bodyBytes.toString(Charsets.UTF_8).take(600)
                    }
                DemoResult(
                    id = scenario.id,
                    ok = response.isSuccessful || scenario.id == "S12",
                    status = response.code,
                    detail =
                        "status ${response.code}\n" +
                            "Traffic: FORWARD $method …\n\n" +
                            detail,
                )
            }
        } catch (e: IOException) {
            DemoResult(scenario.id, false, detail = "error: ${e.message}")
        }
    }

    fun runAll(onProgress: ((DemoScenario, DemoResult) -> Unit)? = null): List<DemoResult> {
        val results = mutableListOf<DemoResult>()
        for (scenario in DemoScenarios.all) {
            val result = run(scenario)
            results.add(result)
            onProgress?.invoke(scenario, result)
            Thread.sleep(300)
        }
        return results
    }
}
