package io.mocklane.sample.integration

import io.mocklane.sample.BuildConfig
import io.mocklane.sdk.MocklaneOkHttp
import okhttp3.OkHttpClient

/**
 * Debug-only OkHttp client for the sample.
 *
 * A real app attaches the same interceptor last in its own builder.
 */
object MocklaneBootstrap {
    fun isEnabled(): Boolean = BuildConfig.DEBUG

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .addInterceptor(MocklaneOkHttp.interceptor(enabled = BuildConfig.DEBUG))
            .build()
    }
}
