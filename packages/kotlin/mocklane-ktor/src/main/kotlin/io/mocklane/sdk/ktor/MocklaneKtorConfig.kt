package io.mocklane.sdk.ktor

import io.mocklane.sdk.MocklaneConfig

/** Installation-time options for [MocklaneKtor]. */
public class MocklaneKtorConfig {
    /**
     * SDK config for this client. Required: set it at installation so the app
     * names its build flag explicitly. The plugin fails at client construction
     * when it is missing.
     */
    public var config: MocklaneConfig? = null
}
