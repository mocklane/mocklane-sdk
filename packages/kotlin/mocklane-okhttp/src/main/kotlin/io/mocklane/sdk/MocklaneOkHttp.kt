@file:OptIn(MocklaneInternalApi::class)

package io.mocklane.sdk

import io.mocklane.sdk.internal.GatewayProbe
import io.mocklane.sdk.internal.HttpGatewayProbe
import io.mocklane.sdk.internal.MocklaneCookieInterceptor
import io.mocklane.sdk.internal.MocklaneOkHttpInterceptor
import io.mocklane.sdk.internal.NeverReachableProbe
import okhttp3.CookieJar
import okhttp3.OkHttpClient

/**
 * OkHttp adapter for Mocklane.
 *
 * `install` returns a new client: it keeps every interceptor, cache, and
 * `CookieJar` already configured on [client] and adds the Mocklane rewrite
 * interceptor. Cookies stay scoped to the embedded origin instead of the
 * gateway host.
 *
 * ```kotlin
 * val client = MocklaneOkHttp.install(
 *     OkHttpClient.Builder().cookieJar(myJar).build(),
 *     MocklaneConfig(enabled = BuildConfig.DEBUG),
 * )
 * ```
 *
 * Call `install` after configuring the client (including its `CookieJar`); the
 * jar is captured at install time, so a later `newBuilder().cookieJar(...)`
 * derived from the returned client is not scoped by Mocklane.
 *
 * Interception is opt-in; the disabled form is a pass-through so release builds
 * cannot capture by accident.
 */
public object MocklaneOkHttp {
    /** Shorthand for `install(client, MocklaneConfig(enabled = enabled))`. */
    @JvmStatic
    public fun install(client: OkHttpClient, enabled: Boolean): OkHttpClient =
        install(client, MocklaneConfig(enabled = enabled))

    /**
     * Build a Mocklane client from [client].
     *
     * An enabled config also binds the shared [Mocklane.log] / [Mocklane.rewrite]
     * runtime. A disabled config leaves the runtime of an already enabled
     * adapter untouched.
     *
     * Called twice on the same client, the first install wins.
     */
    @JvmStatic
    public fun install(client: OkHttpClient, config: MocklaneConfig): OkHttpClient {
        // The first install wins; a second call must not bind a new runtime.
        if (alreadyInstalled(client)) return client
        val resolved = Mocklane.bind(config)
        val probe: GatewayProbe =
            if (resolved.enabled) HttpGatewayProbe(resolved) else NeverReachableProbe
        return installWithProbe(client, resolved, probe)
    }

    internal fun installWithProbe(
        client: OkHttpClient,
        config: MocklaneConfig,
        probe: GatewayProbe,
    ): OkHttpClient {
        if (alreadyInstalled(client)) return client
        val cookieJar: CookieJar? =
            if (config.enabled) {
                client.cookieJar.takeUnless { it === CookieJar.NO_COOKIES }
            } else {
                null
            }
        return client
            .newBuilder()
            .addInterceptor(MocklaneOkHttpInterceptor(config, probe))
            .addNetworkInterceptor(MocklaneCookieInterceptor(config, cookieJar))
            .build()
    }

    private fun alreadyInstalled(client: OkHttpClient): Boolean =
        client.interceptors.any { it is MocklaneOkHttpInterceptor } ||
            client.networkInterceptors.any { it is MocklaneCookieInterceptor }
}
