package io.mocklane.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DeviceMetadataTest {
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
