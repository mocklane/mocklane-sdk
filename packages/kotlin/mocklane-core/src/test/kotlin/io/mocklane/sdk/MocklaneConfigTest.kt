package io.mocklane.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MocklaneConfigTest {
    @Test
    fun defaultIsDisabled() {
        assertFalse(MocklaneConfig().enabled)
    }

    @Test
    fun fillsMissingDeviceFields() {
        val config =
            MocklaneConfig(
                device =
                    DeviceMetadata(
                        deviceName = "custom-name",
                        appVersion = "1.2.3",
                    ),
            ).withPlatformDefaults()

        val device = config.device!!
        assertEquals("custom-name", device.deviceName)
        assertEquals("1.2.3", device.appVersion)
        assertTrue(
            device.deviceId!!.startsWith("android:") || device.deviceId!!.startsWith("jvm:"),
        )
        assertFalse(device.os.isNullOrBlank())
    }

    @Test
    fun fillsDeviceWhenConfigHasNone() {
        val device = MocklaneConfig().withPlatformDefaults().device!!
        assertTrue(
            device.deviceId!!.startsWith("android:") || device.deviceId!!.startsWith("jvm:"),
        )
        assertFalse(device.deviceName.isNullOrBlank())
    }

    @Test
    fun rejectsBlankHost() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(host = " ")
        }
    }

    @Test
    fun rejectsOutOfRangePort() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(port = 0)
        }
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(port = 65536)
        }
    }

    @Test
    fun rejectsNonPositiveProbeTimeout() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(probeTimeoutMs = 0)
        }
    }
}
