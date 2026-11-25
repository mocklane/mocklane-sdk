import SwiftUI
import Mocklane

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var out = "Ready."
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mocklane SDK demo")
                    .font(.largeTitle.bold())

                Text(
                    "Same scenario catalog as web, Android, Flutter, and Swift CLI. "
                        + "Desktop Listening on :6625. Physical device: USB + Connect iOS."
                )
                .foregroundStyle(.secondary)
                .font(.subheadline)

                HStack(spacing: 12) {
                    Button("Run all") {
                        Task { await runAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)

                    Button("Clear output") {
                        out = "Ready."
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }

                List {
                    ForEach(DemoScenarios.all) { scenario in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(scenario.id) \(scenario.label)")
                                    .font(.headline)
                                Text(pathLabel(scenario))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Run") {
                                Task { await runOne(scenario) }
                            }
                            .disabled(busy)
                        }
                    }
                }
                .listStyle(.plain)

                ScrollView {
                    Text(out)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
            }
            .padding(16)
            .navigationBarHidden(true)
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Mocklane.refreshUsbBridge()
                }
            }
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-MocklaneSmoke") else { return }
                #if targetEnvironment(simulator)
                try? await Task.sleep(nanoseconds: 300_000_000)
                #else
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                #endif
                await runAll()
            }
        }
    }

    private func pathLabel(_ scenario: DemoScenario) -> String {
        if scenario.kind == "sdk_log" { return "POST /__mocklane/v1/log" }
        guard let url = scenario.url, let parsed = URL(string: url) else { return scenario.method ?? "" }
        return "\(scenario.method ?? "") \(parsed.path)\(parsed.query.map { "?\($0)" } ?? "")"
    }

    private func runOne(_ scenario: DemoScenario) async {
        busy = true
        out = "Running \(scenario.id) …"
        defer { busy = false }
        let result = await DemoRunner.run(scenario)
        out = "[\(result.id)] \(result.ok ? "OK" : "FAIL")\n\(result.detail)"
    }

    private func runAll() async {
        busy = true
        out = "Running all scenarios …\n"
        var lines: [String] = []
        _ = await DemoRunner.runAll { _, result in
            lines.append("[\(result.id)] \(result.ok ? "OK" : "FAIL") status=\(result.status.map(String.init) ?? "—")")
            out = lines.joined(separator: "\n")
        }
        lines.append("\n=== Run all complete ===")
        out = lines.joined(separator: "\n")
        busy = false
    }
}

#Preview {
    ContentView()
}
