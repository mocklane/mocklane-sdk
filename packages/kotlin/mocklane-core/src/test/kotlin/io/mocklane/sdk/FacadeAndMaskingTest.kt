package io.mocklane.sdk

import io.mocklane.sdk.internal.Masking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FacadeAndMaskingTest {
    @Test
    fun maskingRedactsSecrets() {
        assertEquals(
            mapOf("Authorization" to "[REDACTED]", "Content-Type" to "application/json"),
            Masking.maskHeaders(
                mapOf("Authorization" to "Bearer x", "Content-Type" to "application/json"),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val masked =
            Masking.maskJsonValue(mapOf("user" to "a", "password" to "p")) as Map<String, Any?>
        assertEquals("a", masked["user"])
        assertEquals("[REDACTED]", masked["password"])
    }

    @Test
    fun maskingRedactsNestedSecrets() {
        @Suppress("UNCHECKED_CAST")
        val masked =
            Masking.maskJsonValue(
                mapOf(
                    "user" to mapOf("name" to "a", "api_key" to "k"),
                    "items" to listOf(mapOf("token" to "t1"), "plain", 7),
                ),
            ) as Map<String, Any?>

        val user = masked["user"] as Map<String, Any?>
        assertEquals("a", user["name"])
        assertEquals("[REDACTED]", user["api_key"])

        val items = masked["items"] as List<Any?>
        assertEquals("[REDACTED]", (items[0] as Map<String, Any?>)["token"])
        assertEquals("plain", items[1])
        assertEquals(7, items[2])
    }

    @Test
    fun deviceMetadataFillsPlatformDefaults() {
        val filled =
            DeviceMetadata(deviceName = "custom-name").withPlatformDefaults(appVersion = "1.2.3")
        assertEquals("custom-name", filled.deviceName)
        assertEquals("1.2.3", filled.appVersion)
        assertTrue(
            filled.deviceId!!.startsWith("android:") || filled.deviceId!!.startsWith("jvm:"),
        )
        assertFalse(filled.os.isNullOrBlank())
    }

    @Test
    fun platformDefaultProducesId() {
        val meta = DeviceMetadata.platformDefault(appVersion = "9.9.9")
        assertTrue(
            meta.deviceId!!.startsWith("android:") || meta.deviceId!!.startsWith("jvm:"),
        )
        assertFalse(meta.deviceName.isNullOrBlank())
        assertEquals("9.9.9", meta.appVersion)
    }
}
