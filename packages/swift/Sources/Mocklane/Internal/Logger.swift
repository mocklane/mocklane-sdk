import Foundation

protocol LoggerTransport: Sendable {
    func send(message: String, level: LogLevel, tag: String?) async
}

final class HttpLoggerTransport: LoggerTransport, @unchecked Sendable {
    private let config: MocklaneConfig
    private let session: URLSession
    private let path: String

    init(config: MocklaneConfig, session: URLSession? = nil, path: String = "/__mocklane/v1/log") {
        self.config = config
        self.path = path
        if let session {
            self.session = session
        } else {
            let conf = URLSessionConfiguration.ephemeral
            conf.protocolClasses = []
            self.session = URLSession(configuration: conf)
        }
    }

    func send(message: String, level: LogLevel, tag: String?) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var body: [String: Any] = [
            "message": Masking.maskJSONString(message),
            "level": level.rawValue,
            "ts": formatter.string(from: Date()),
        ]
        if let tag { body["tag"] = tag }
        if let device = config.device {
            var d: [String: String] = [:]
            if let v = device.deviceId { d["deviceId"] = v }
            if let v = device.deviceName { d["deviceName"] = v }
            if let v = device.os { d["os"] = v }
            if let v = device.appVersion { d["appVersion"] = v }
            if !d.isEmpty { body["device"] = d }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: config.logURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        DeviceHeaders.apply(config.device, to: &request)
        request.httpBody = data
        _ = try? await session.data(for: request)
    }
}

final class Logger: @unchecked Sendable {
    private let transport: LoggerTransport

    init(transport: LoggerTransport) {
        self.transport = transport
    }

    func log(_ message: String, level: LogLevel = .info, tag: String? = nil) {
        Task {
            await transport.send(message: message, level: level, tag: tag)
        }
    }
}

enum DeviceHeaders {
    static func apply(_ device: DeviceMetadata?, to request: inout URLRequest) {
        guard let device else { return }
        if let v = device.deviceId {
            request.setValue(v, forHTTPHeaderField: "X-Mocklane-Device-Id")
        }
        if let v = device.deviceName {
            request.setValue(v, forHTTPHeaderField: "X-Mocklane-Device-Name")
        }
        if let v = device.os {
            request.setValue(v, forHTTPHeaderField: "X-Mocklane-Os")
        }
        if let v = device.appVersion {
            request.setValue(v, forHTTPHeaderField: "X-Mocklane-App-Version")
        }
    }
}
