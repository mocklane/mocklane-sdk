@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.HttpGatewayProbe
import io.mocklane.sdk.internal.MocklaneOkHttpInterceptor
import io.mocklane.sdk.internal.NeverReachableProbe
import okhttp3.Interceptor

/**
 * OkHttp adapter for Mocklane.
 *
 * Add the returned interceptor **last** in the application interceptor chain,
 * after your auth / header interceptors. Interception is opt-in; the disabled
 * form is a pass-through so release builds cannot capture by accident.
 */
public object MocklaneOkHttp {
    /** Shorthand for `interceptor(MocklaneConfig(enabled = enabled))`. */
    @JvmStatic
    public fun interceptor(enabled: Boolean): Interceptor =
        interceptor(MocklaneConfig(enabled = enabled))

    /**
     * Build an interceptor from [config].
     *
     * An enabled config also binds the shared [Mocklane.log] / [Mocklane.rewrite]
     * runtime. A disabled config leaves the runtime of an already enabled
     * adapter untouched.
     */
    @JvmStatic
    public fun interceptor(config: MocklaneConfig): Interceptor {
        val resolved = Mocklane.bind(config)
        if (!resolved.enabled) {
            return MocklaneOkHttpInterceptor(resolved, NeverReachableProbe)
        }
        return MocklaneOkHttpInterceptor(resolved, HttpGatewayProbe(resolved))
    }
}
