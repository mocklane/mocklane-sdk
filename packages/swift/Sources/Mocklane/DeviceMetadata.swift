import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Device labels shown in Mocklane Desktop's Traffic view.
public struct DeviceMetadata: Sendable, Equatable {
    public let deviceId: String?
    public let deviceName: String?
    public let os: String?
    public let appVersion: String?

    public init(
        deviceId: String? = nil,
        deviceName: String? = nil,
        os: String? = nil,
        appVersion: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.os = os
        self.appVersion = appVersion
    }

    /// Fill null fields from [platformDefault] so Traffic can group devices.
    public func withPlatformDefaults(
        appVersion: String? = nil
    ) -> DeviceMetadata {
        let base = DeviceMetadata.platformDefault(appVersion: appVersion ?? self.appVersion)
        return DeviceMetadata(
            deviceId: deviceId ?? base.deviceId,
            deviceName: deviceName ?? base.deviceName,
            os: os ?? base.os,
            appVersion: self.appVersion ?? base.appVersion
        )
    }

    /// Best-effort iOS identity. Uses `identifierForVendor` (not hardware UDID)
    /// plus the user-facing device name for Desktop Connect registry matching.
    public static func platformDefault(appVersion: String? = nil) -> DeviceMetadata {
        #if canImport(UIKit) && !os(watchOS)
        let device = UIDevice.current
        let vendor = device.identifierForVendor?.uuidString
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = device.model
        let displayName = name.isEmpty ? model : name
        let version =
            appVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return DeviceMetadata(
            deviceId: vendor.map { "ios:\($0)" },
            deviceName: displayName,
            os: "\(device.systemName) \(device.systemVersion)",
            appVersion: version
        )
        #else
        return DeviceMetadata(
            deviceId: nil,
            deviceName: "Mac",
            os: "macOS",
            appVersion: appVersion
        )
        #endif
    }
}
