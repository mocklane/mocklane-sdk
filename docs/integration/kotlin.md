# Kotlin / Android / JVM

Packages: [`mocklane-okhttp`, `mocklane-ktor`](../../packages/kotlin/README.md)

## Install

Depend on one adapter from the standard `mavenCentral()` repository:

```kotlin
// app/build.gradle.kts — OkHttp / Retrofit apps
debugImplementation("io.github.mocklane:mocklane-okhttp:0.1.1")

// Ktor apps
debugImplementation("io.github.mocklane:mocklane-ktor:0.1.1")
```

`mocklane-core` comes along transitively.

## Minimal integration

**OkHttp** — add the interceptor last, after auth/header interceptors:

```kotlin
val client = OkHttpClient.Builder()
  .addInterceptor(authInterceptor)
  .addInterceptor(MocklaneOkHttp.interceptor(enabled = BuildConfig.DEBUG))
  .build()
```

**Ktor** — install the plugin with your other plugins:

```kotlin
val client = HttpClient {
  install(MocklaneKtor) {
    config = MocklaneConfig(enabled = BuildConfig.DEBUG)
  }
}
```

## Verify

The request appears as `GET /https://api.example.com/v1/me` in Traffic, and
`Mocklane.log("…")` appears as `SDK_LOG`.

## Advanced options

### Custom gateway

The default is `127.0.0.1:6625`. Pass a `MocklaneConfig`:

```kotlin
val config = MocklaneConfig(
  port = 7000,          // or host = "192.168.1.10"
  enabled = BuildConfig.DEBUG,
)

val client = existingClient.newBuilder()
  .addInterceptor(MocklaneOkHttp.interceptor(config))
  .build()
```

### Other options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | `false` | Opt-in; set it from your build flag |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → throw |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |

Full reference: [`packages/kotlin/README.md`](../../packages/kotlin/README.md).

## Android setup

Android 9+ blocks cleartext HTTP by default, and the gateway is plain HTTP on
loopback (`http://127.0.0.1:6625`). Allow cleartext for loopback only — keep
HTTPS-only everywhere else:

```xml
<!-- res/xml/network_security_config.xml -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
```

```xml
<!-- AndroidManifest.xml -->
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ... >
```

For the emulator or a physical device, open Mocklane Desktop and run
**Connect Android** once — it sets up the `adb reverse tcp:6625 tcp:6625`
needed for `127.0.0.1` to reach your Mac. The app then needs no host or port
configuration.
