package io.mocklane.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MocklaneConfigTest {
    @Test
    fun carriesEnabledFlag() {
        assertFalse(MocklaneConfig(enabled = false).enabled)
        assertTrue(MocklaneConfig(enabled = true).enabled)
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
                enabled = false,
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
        val device = MocklaneConfig(enabled = false).withPlatformDefaults().device!!
        assertTrue(
            device.deviceId!!.startsWith("android:") || device.deviceId!!.startsWith("jvm:"),
        )
        assertFalse(device.deviceName.isNullOrBlank())
    }

    @Test
    fun rejectsBlankHost() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(host = " ", enabled = false)
        }
    }

    @Test
    fun rejectsOutOfRangePort() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(port = 0, enabled = false)
        }
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(port = 65536, enabled = false)
        }
    }

    @Test
    fun rejectsNonPositiveProbeTimeout() {
        assertFailsWith<IllegalArgumentException> {
            MocklaneConfig(probeTimeoutMs = 0, enabled = false)
        }
    }
}
