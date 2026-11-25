@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk.internal

import io.mocklane.sdk.DeviceMetadata
import io.mocklane.sdk.LogLevel
import io.mocklane.sdk.MocklaneInternalApi
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal interface LoggerTransport {
    fun send(message: String, level: LogLevel, tag: String?)

    /** Release resources owned by the transport. */
    fun close() {}
}

/**
 * Best-effort `POST /__mocklane/v1/log` transport.
 *
 * Runs on a daemon thread and never throws into the host app. Uses
 * [HttpURLConnection] so core has no HTTP-client dependency.
 *
 * The queue is bounded: a log flood drops the oldest pending entries instead of
 * growing memory without limit.
 */
internal class HttpLoggerTransport(
    private val host: String,
    private val port: Int,
    private val device: DeviceMetadata? = null,
    private val path: String = "/__mocklane/v1/log",
    private val timeoutMs: Long = DEFAULT_LOG_TIMEOUT_MS,
    private val executor: ExecutorService = defaultLogExecutor(),
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

    override fun close() {
        executor.shutdownNow()
    }
}

internal class Logger(private val transport: LoggerTransport) {
    fun log(message: String, level: LogLevel = LogLevel.INFO, tag: String? = null) {
        runCatching { transport.send(message, level, tag) }
    }

    fun close() {
        runCatching { transport.close() }
    }
}

private const val DEFAULT_LOG_TIMEOUT_MS = 2_000L
private const val LOG_QUEUE_CAPACITY = 256

private fun defaultLogExecutor(): ExecutorService =
    ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        LinkedBlockingQueue(LOG_QUEUE_CAPACITY),
        ThreadFactory { runnable -> Thread(runnable, "mocklane-log").apply { isDaemon = true } },
        ThreadPoolExecutor.DiscardOldestPolicy(),
    )

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
    parts += "\"ts\":${jsonString(utcTimestamp())}"
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

/** ISO-8601 UTC timestamp with milliseconds, matching the other SDKs. */
private fun utcTimestamp(): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date())
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
                else ->
                    if (c < ' ') {
                        append("\\u")
                        append(c.code.toString(16).padStart(4, '0'))
                    } else {
                        append(c)
                    }
            }
        }
        append('"')
    }
