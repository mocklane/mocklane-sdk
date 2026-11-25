import Foundation
import SwiftUI
import Mocklane

/// Debug-only URLSession for the sample.
///
/// A real app creates the same kind of session in its own networking layer.
enum MocklaneBootstrap {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    // Longer probe timeout for the physical-device USB tunnel; failOpen keeps
    // requests on the real host while the bridge reconnects.
    static let session: URLSession = Mocklane.urlSession(
        config: MocklaneConfig(enabled: isEnabled, probeTimeoutMs: 4000)
    )
}

@main
struct MocklaneIOSSampleApp: App {
    init() {
        // Create the session once so the USB bridge and logging are ready.
        _ = MocklaneBootstrap.session
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
