@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.internal

import io.mocklane.sdk.DeviceMetadata
import io.mocklane.sdk.LogLevel
import io.mocklane.sdk.MocklaneInternalApi
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal fun interface LoggerTransport {
    fun send(message: String, level: LogLevel, tag: String?)
}

/**
 * Best-effort `POST /__mocklane/v1/log` transport.
 *
 * Runs on a daemon thread and never throws into the host app. Uses
 * [HttpURLConnection] so core has no HTTP-client dependency.
 */
internal class HttpLoggerTransport(
    private val host: String,
    private val port: Int,
    private val device: DeviceMetadata? = null,
    private val path: String = "/__mocklane/v1/log",
    private val timeoutMs: Long = DEFAULT_LOG_TIMEOUT_MS,
    private val executor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "mocklane-log").apply { isDaemon = true }
        },
) : LoggerTransport {
    override fun send(message: String, level: LogLevel, tag: String?) {
        executor.execute {
            runCatching {
                val bytes = buildLogJson(message, level, tag, device).toByteArray(Charsets.UTF_8)
                val connection =
                    (URL("http://$host:$port$path").openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = timeoutMs.toTimeoutMillis()
                        readTimeout = timeoutMs.toTimeoutMillis()
                        doOutput = true
                        useCaches = false
                        setFixedLengthStreamingMode(bytes.size)
                        setRequestProperty("Content-Type", "application/json; charset=utf-8")
                        DeviceHeaders.values(device).forEach { (name, value) ->
                            setRequestProperty(name, value)
                        }
                    }
                try {
                    connection.outputStream.use { it.write(bytes) }
                    connection.responseCode
                } finally {
                    connection.disconnect()
                }
            }
        }
    }
}

internal class Logger(private val transport: LoggerTransport) {
    fun log(message: String, level: LogLevel = LogLevel.INFO, tag: String? = null) {
        runCatching { transport.send(message, level, tag) }
    }
}

private const val DEFAULT_LOG_TIMEOUT_MS = 2_000L

private fun Long.toTimeoutMillis(): Int =
    coerceAtLeast(1L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

private fun buildLogJson(
    message: String,
    level: LogLevel,
    tag: String?,
    device: DeviceMetadata?,
): String {
    val parts = mutableListOf<String>()
    parts += "\"message\":${jsonString(message)}"
    parts += "\"level\":${jsonString(level.name.lowercase())}"
    parts += "\"ts\":${jsonString(Instant.now().toString())}"
    if (tag != null) parts += "\"tag\":${jsonString(tag)}"
    if (device != null) {
        val d = mutableListOf<String>()
        device.deviceId?.let { d += "\"deviceId\":${jsonString(it)}" }
        device.deviceName?.let { d += "\"deviceName\":${jsonString(it)}" }
        device.os?.let { d += "\"os\":${jsonString(it)}" }
        device.appVersion?.let { d += "\"appVersion\":${jsonString(it)}" }
        if (d.isNotEmpty()) parts += "\"device\":{${d.joinToString(",")}}"
    }
    return "{${parts.joinToString(",")}}"
}

private fun jsonString(value: String): String =
    buildString {
        append('"')
        value.forEach { c ->
            when (c) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(c)
            }
        }
        append('"')
    }
