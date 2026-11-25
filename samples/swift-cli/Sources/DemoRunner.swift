import Foundation
import Mocklane

enum DemoRunner {
    static func run(_ scenario: DemoScenario) async -> DemoResult {
        if scenario.kind == "sdk_log" {
            return runLog(scenario)
        }
        return await runApi(scenario)
    }

    private static func runLog(_ scenario: DemoScenario) -> DemoResult {
        let level: LogLevel
        switch scenario.logLevel?.lowercased() {
        case "warn": level = .warn
        case "error": level = .error
        case "debug": level = .debug
        default: level = .info
        }
        Mocklane.log(scenario.logMessage ?? "", level: level, tag: scenario.logTag)
        return DemoResult(
            id: scenario.id,
            ok: true,
            status: nil,
            detail: "SDK_LOG \(scenario.logLevel ?? "info") tag=\(scenario.logTag ?? "")"
        )
    }

    private static func runApi(_ scenario: DemoScenario) async -> DemoResult {
        guard let urlString = scenario.url, let url = URL(string: urlString) else {
            return DemoResult(id: scenario.id, ok: false, status: nil, detail: "missing url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = scenario.method
        for (key, value) in scenario.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = scenario.body {
            request.httpBody = body.data(using: .utf8)
            if let contentType = scenario.contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let session = MocklaneBootstrap.session
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail: String
            if scenario.responseKind == "binary" {
                detail = "\(data.count) bytes"
            } else {
                let text = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                detail = String(text.prefix(400))
            }
            let ok = (200 ..< 300).contains(status) || scenario.id == "S12"
            return DemoResult(
                id: scenario.id,
                ok: ok,
                status: status,
                detail: "status \(status) — \(detail)"
            )
        } catch {
            return DemoResult(id: scenario.id, ok: false, status: nil, detail: "error: \(error.localizedDescription)")
        }
    }
}

struct DemoResult {
    let id: String
    let ok: Bool
    let status: Int?
    let detail: String
}
