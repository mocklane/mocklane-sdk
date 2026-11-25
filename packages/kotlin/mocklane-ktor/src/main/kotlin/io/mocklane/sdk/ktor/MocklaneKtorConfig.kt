package io.mocklane.sdk.ktor

import io.mocklane.sdk.MocklaneConfig

/** Installation-time options for [MocklaneKtor]. */
public class MocklaneKtorConfig {
    /**
     * SDK config for this client. `enabled` is opt-in (`false` by default), so
     * pass your build flag at installation.
     */
    public var config: MocklaneConfig = MocklaneConfig()
}
