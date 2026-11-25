# Kotlin / Android / JVM

Packages: [`mocklane-okhttp`, `mocklane-ktor`](../../packages/kotlin/README.md) · Overview: [`INTEGRATION.md`](../INTEGRATION.md)

The SDK has one adapter per HTTP client. Both use the same config, log runtime, and rewrite rules, so OkHttp and Ktor requests behave the same. While interception is enabled, the SDK sends absolute `http(s)` requests to `http://127.0.0.1:6625/<original-url>` instead of their original URL.

Requirements: JDK 17 toolchain.

## Install

Add the adapter for the client your app uses:

```kotlin
// app/build.gradle.kts

// OkHttp / Retrofit
debugImplementation("io.github.mocklane:mocklane-okhttp:0.1.1")

// Ktor
debugImplementation("io.github.mocklane:mocklane-ktor:0.1.1")
```

## OkHttp / Retrofit

`MocklaneOkHttp.install` returns a new client built from the one you pass in. Use the returned client for every API call:

```kotlin
val client = MocklaneOkHttp.install(existingClient, enabled = BuildConfig.DEBUG)
```

Pass `enabled` explicitly so traffic you did not intend, such as production traffic, is never captured.

### What the adapter adds

- An **application interceptor** that rewrites absolute `http(s)` URLs to the gateway URL and adds device headers. It is appended after the client's existing interceptors, so auth and header interceptors you added earlier still run first.
- A **network interceptor** that keeps your `CookieJar` keyed to the embedded origin: `Set-Cookie` is parsed against the real origin, saved there, and stripped before OkHttp's own cookie handling sees the gateway URL.

The client needs its interceptors, cache, and `CookieJar` configured before you call `install`. The jar is captured at install time; a `cookieJar(...)` set later on the returned client is not scoped by Mocklane. Calling `install` twice on the same client keeps the first install.

### Gateway, cache, and redirects

The default gateway is `127.0.0.1:6625`. For another host or port, pass a `MocklaneConfig`:

```kotlin
val config = MocklaneConfig(
  port = 7000,          // or host = "192.168.1.10"
  enabled = BuildConfig.DEBUG,
)

val client = MocklaneOkHttp.install(existingClient, config)
```

If the client has an OkHttp `Cache`, responses are stored under the gateway URL (`http://127.0.0.1:6625/<origin>/<path>`), not their original URL. Debug builds rarely enable a cache; disable it while capturing if cache hits hide the traffic you expect.

The Mocklane app rewrites same-origin redirects to gateway-prefixed URLs, whether `Location` is absolute or relative. The hop stays captured and keeps `Authorization` and `Cookie` headers.

## Ktor

Install the plugin on the `HttpClient` you use for API calls:

```kotlin
val client = HttpClient {
  install(MocklaneKtor) {
    config = MocklaneConfig(enabled = BuildConfig.DEBUG)
  }
}
```

The plugin is engine-agnostic: CIO, OkHttp, Android, Darwin, and `MockEngine` all work. It runs before the engine sends the request, so it sees the final URL, query, and body content type. WebSocket handshakes and gRPC bodies are skipped. The plugin must be installed after plugins that set request headers (for example `WebSockets`) so those headers are visible to the rewrite.

For another gateway, pass the settings through the plugin config:

```kotlin
val client = HttpClient {
  install(MocklaneKtor) {
    config = MocklaneConfig(port = 7000, enabled = BuildConfig.DEBUG)
  }
}
```

A Ktor client plugin has no cookie hook. `HttpCookies` keys cookies by request URL, which is the gateway URL after the rewrite, so cookies set through the gateway may be stored under `127.0.0.1:6625` and not shared with clients that skip Mocklane. If cookie-bound auth matters, prefer `MocklaneOkHttp.install`, or use a cookie manager that keys to the original URL.

## Android setup

Android 9 and later block cleartext HTTP by default, and the gateway is plain HTTP on loopback (`http://127.0.0.1:6625`). The network security config allows cleartext for loopback only and keeps every other host HTTPS-only:

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

For the emulator or a physical device, run **Connect Android** in the Mocklane app once. It sets up `adb reverse tcp:6625 tcp:6625`, which makes `127.0.0.1` on the device reach your computer, so the app needs no host or port configuration.

## Options

`MocklaneConfig` carries every option:

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | — (required) | Pass your build flag; `true` → intercept, `false` → pass-through |
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → throw |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Device labels in Traffic |

A disabled adapter stays installed but is a pass-through. It does not clear the log runtime of an already enabled adapter, so one enabled client keeps `Mocklane.log` working while other clients stay pass-through.

Full reference: [`packages/kotlin/README.md`](../../packages/kotlin/README.md).

## Local checkout

For SDK development, point the app at the package directories instead of Maven Central:

```kotlin
// settings.gradle.kts
include(":mocklane-core", ":mocklane-okhttp")
project(":mocklane-core").projectDir = file("<path-to-sdk>/packages/kotlin/mocklane-core")
project(":mocklane-okhttp").projectDir = file("<path-to-sdk>/packages/kotlin/mocklane-okhttp")
```

Use `mocklane-ktor` in place of `mocklane-okhttp` for a Ktor app.

## Logging and privacy

`Mocklane.log(message, level, tag)` posts the message to the gateway, and the Mocklane app stores the captured traffic. The Kotlin SDK has no JSON parser and sends messages as-is, so mask secrets in your own code before logging:

```kotlin
Mocklane.log(redactSecrets(payload)) // `redactSecrets` is your helper
```

Request and response bodies are never redacted.

The gateway is plain HTTP without authentication. The `host` setting must stay on loopback (`127.0.0.1`); pointing it at a LAN address sends captured credentials to everyone on that network.
