package io.mocklane.sdk

import java.net.InetAddress

/** Device labels shown in Mocklane Desktop's Traffic view. */
data class DeviceMetadata(
    val deviceId: String? = null,
    val deviceName: String? = null,
    val os: String? = null,
    val appVersion: String? = null,
) {
    /**
     * Fill any null fields from [platformDefault] so Traffic can group by a
     * stable id without every app inventing labels.
     */
    fun withPlatformDefaults(appVersion: String? = null): DeviceMetadata {
        val base = platformDefault(appVersion = appVersion ?: this.appVersion)
        return DeviceMetadata(
            deviceId = deviceId ?: base.deviceId,
            deviceName = deviceName ?: base.deviceName,
            os = os ?: base.os,
            appVersion = this.appVersion ?: base.appVersion,
        )
    }

    companion object {
        /**
         * Best-effort device identity for Mocklane Traffic grouping.
         *
         * On Android (when `android.os.Build` is on the classpath): prefers
         * hardware serial, else a stable id from model + fingerprint.
         * On JVM / desktop samples: falls back to host name.
         *
         * Prefer [platformDefaultFromContext] from an Activity/Application when
         * you want [Settings.Secure.ANDROID_ID].
         */
        @JvmStatic
        @JvmOverloads
        fun platformDefault(appVersion: String? = null): DeviceMetadata {
            AndroidBuildReflect.read()?.let { android ->
                return DeviceMetadata(
                    deviceId = "android:${android.idToken}",
                    deviceName = android.model,
                    os = "Android ${android.release}",
                    appVersion = appVersion,
                )
            }
            val host =
                runCatching { InetAddress.getLocalHost().hostName }
                    .getOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?: "host"
            return DeviceMetadata(
                deviceId = "jvm:$host",
                deviceName = host,
                os = System.getProperty("os.name") ?: "jvm",
                appVersion = appVersion,
            )
        }

        /**
         * Android-only helper: pass an Activity/Application `Context` to use
         * `Settings.Secure.ANDROID_ID` when serial is unavailable.
         * Safe no-op fallback to [platformDefault] on non-Android runtimes.
         */
        @JvmStatic
        @JvmOverloads
        fun platformDefaultFromContext(
            context: Any,
            appVersion: String? = null,
        ): DeviceMetadata {
            val androidId = AndroidBuildReflect.androidId(context)
            val base = platformDefault(appVersion)
            if (androidId.isNullOrBlank()) return base
            // Prefer hardware serial already encoded in base when present.
            if (base.deviceId?.startsWith("android:") == true &&
                AndroidBuildReflect.read()?.serial != null
            ) {
                return base
            }
            return base.copy(deviceId = "android:$androidId")
        }
    }
}

/** Optional Android APIs via reflection so this artifact stays pure JVM/OkHttp. */
internal object AndroidBuildReflect {
    data class Info(
        val model: String,
        val release: String,
        val serial: String?,
        val idToken: String,
    )

    fun read(): Info? {
        return runCatching {
            val build = Class.forName("android.os.Build")
            val model =
                (build.getField("MODEL").get(null) as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?: "Android"
            val release =
                runCatching {
                    val version = Class.forName("android.os.Build\$VERSION")
                    version.getField("RELEASE").get(null) as? String
                }.getOrNull() ?: "?"
            val serial = readSerial(build)
            val fingerprint =
                (build.getField("FINGERPRINT").get(null) as? String).orEmpty()
            val idToken =
                serial
                    ?: "model-${sanitize(model)}-${fingerprint.hashCode().toUInt()}"
            Info(model = model, release = release, serial = serial, idToken = idToken)
        }.getOrNull()
    }

    fun androidId(context: Any): String? =
        runCatching {
            val settings = Class.forName("android.provider.Settings\$Secure")
            val resolver = context.javaClass.getMethod("getContentResolver").invoke(context)
            settings
                .getMethod(
                    "getString",
                    Class.forName("android.content.ContentResolver"),
                    String::class.java,
                ).invoke(null, resolver, "android_id") as? String
        }.getOrNull()?.takeIf { it.isNotBlank() }

    private fun readSerial(build: Class<*>): String? =
        runCatching {
            val sdkInt =
                Class.forName("android.os.Build\$VERSION").getField("SDK_INT").getInt(null)
            val raw =
                if (sdkInt >= 26) {
                    build.getMethod("getSerial").invoke(null) as? String
                } else {
                    build.getField("SERIAL").get(null) as? String
                }
            raw?.takeIf {
                it.isNotBlank() &&
                    !it.equals("unknown", ignoreCase = true) &&
                    !it.equals("UNKNOWN", ignoreCase = true)
            }
        }.getOrNull()

    private fun sanitize(value: String): String =
        value.trim().replace(Regex("[^A-Za-z0-9._-]"), "_").take(32).ifBlank { "device" }
}
