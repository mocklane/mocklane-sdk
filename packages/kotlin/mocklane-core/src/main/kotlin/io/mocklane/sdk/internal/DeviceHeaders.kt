package io.mocklane.sdk.internal

import io.mocklane.sdk.DeviceMetadata
import io.mocklane.sdk.MocklaneInternalApi

/** Device labels attached to intercepted requests and SDK logs. */
@MocklaneInternalApi
public object DeviceHeaders {
    public fun values(device: DeviceMetadata?): Map<String, String> {
        if (device == null) return emptyMap()
        val headers = LinkedHashMap<String, String>(4)
        device.deviceId?.let { headers["X-Mocklane-Device-Id"] = it }
        device.deviceName?.let { headers["X-Mocklane-Device-Name"] = it }
        device.os?.let { headers["X-Mocklane-Os"] = it }
        device.appVersion?.let { headers["X-Mocklane-App-Version"] = it }
        return headers
    }
}
