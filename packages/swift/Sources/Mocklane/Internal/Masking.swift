import Foundation

enum Masking {
    static let defaultHeaderKeys: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token",
        "proxy-authorization",
    ]
    static let defaultJsonKeys: Set<String> = [
        "password", "token", "access_token", "refresh_token", "id_token",
        "secret", "client_secret", "api_key", "session", "session_id",
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

    /// Masks secrets inside a JSON-shaped message; returns `message` unchanged
    /// when it is not valid JSON. Any JSON root is accepted — object, array,
    /// or scalar.
    static func maskJSONString(_ message: String) -> String {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(
                  with: data,
                  options: [.fragmentsAllowed]
              ),
              let out = try? JSONSerialization.data(
                  withJSONObject: maskJSONValue(json),
                  options: [.sortedKeys, .fragmentsAllowed]
              ),
              let str = String(data: out, encoding: .utf8)
        else {
            return message
        }
        return str
    }
}
