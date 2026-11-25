import Foundation
import Mocklane

/// Debug-only URLSession for the sample.
enum MocklaneBootstrap {
    static let session: URLSession = Mocklane.urlSession(
        config: MocklaneConfig(
            enabled: true,
            device: DeviceMetadata(
                deviceId: "swift-sample-1",
                deviceName: "swift-sample",
                os: "macos",
                appVersion: "0.1.1"
            )
        )
    )
}

@main
struct MocklaneSwiftSampleApp {
    static func main() async {
        _ = MocklaneBootstrap.session
        print("Mocklane session ready — Desktop should be Listening :6625")
        print("Running \(DemoScenarios.all.count) scenarios …\n")

        var failed = 0
        for scenario in DemoScenarios.all {
            let result = await DemoRunner.run(scenario)
            let status = result.status.map(String.init) ?? "—"
            print("[\(result.id)] \(result.ok ? "OK" : "FAIL") status=\(status) \(result.detail.prefix(120))")
            if !result.ok { failed += 1 }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        if failed > 0 {
            fputs("FAILED \(failed) scenario(s)\n", stderr)
            exit(1)
        }
        print("\n=== All scenarios complete ===")
    }
}
