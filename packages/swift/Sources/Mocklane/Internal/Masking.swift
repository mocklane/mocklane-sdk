import Foundation

enum Masking {
    static let defaultHeaderKeys: Set<String> = [
        "authorization", "cookie", "x-api-key", "proxy-authorization",
    ]
    static let defaultJsonKeys: Set<String> = [
        "password", "token", "access_token", "refresh_token", "secret", "api_key",
    ]

    static func maskHeaders(
        _ headers: [String: String],
        headerKeys: Set<String> = defaultHeaderKeys,
        replacement: String = "[REDACTED]"
    ) -> [String: String] {
        headers.reduce(into: [:]) { result, pair in
            if headerKeys.contains(pair.key.lowercased()) {
                result[pair.key] = replacement
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    static func maskJSONValue(
        _ value: Any,
        jsonKeys: Set<String> = defaultJsonKeys,
        replacement: String = "[REDACTED]"
    ) -> Any {
        if let array = value as? [Any] {
            return array.map { maskJSONValue($0, jsonKeys: jsonKeys, replacement: replacement) }
        }
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                if jsonKeys.contains(pair.key.lowercased()) {
                    result[pair.key] = replacement
                } else {
                    result[pair.key] = maskJSONValue(
                        pair.value,
                        jsonKeys: jsonKeys,
                        replacement: replacement
                    )
                }
            }
        }
        return value
    }

    static func maskJSONString(_ message: String) -> String {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let masked = maskJSONValue(json) as? [String: Any],
              let out = try? JSONSerialization.data(
                  withJSONObject: masked,
                  options: [.sortedKeys]
              ),
              let str = String(data: out, encoding: .utf8)
        else {
            return message
        }
        return str
    }
}
