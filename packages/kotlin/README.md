# mocklane (Kotlin)

Debug-only HTTP interception for Android / JVM. Same gateway contract as
JS/Dart/Swift:

`https://api.example.com/v1/x` → `http://127.0.0.1:6625/https://api.example.com/v1/x`

Fail-open if Desktop is down. Gate with `BuildConfig.DEBUG` in the host app.

## Modules

One shared core, one thin adapter per HTTP client. Add only the artifact for the
client you use:

| Module | Public entry point | Use when |
|--------|--------------------|----------|
| `mocklane-core` | `MocklaneConfig`, `DeviceMetadata`, `Mocklane.log`, `Mocklane.rewrite` | Shared by adapters; not added directly by apps |
| `mocklane-okhttp` | `MocklaneOkHttp.interceptor(...)` | OkHttp / Retrofit |
| `mocklane-ktor` | `MocklaneKtor` | Ktor client (any engine) |

All adapters share the same config, runtime, log, device labels, and rewrite
rules. Adding another client later means adding one adapter artifact, not
forking the SDK. If an app uses both OkHttp and Ktor, include `mocklane-core`
once and both adapter modules.

Adapters only rewrite the URL and add device headers; request and response
bodies are passed through untouched, so streaming and large uploads behave the
same as they do without Mocklane.

## Install (Maven Central)

```kotlin
// app/build.gradle.kts — OkHttp / Retrofit apps
debugImplementation("io.github.mocklane:mocklane-okhttp:0.1.1")

// Ktor apps
debugImplementation("io.github.mocklane:mocklane-ktor:0.1.1")
```

One adapter line is enough — `mocklane-core` comes along transitively.
Standard `mavenCentral()` repository; no extra repository URL or
authentication is needed.

## Gradle path dependency

```kotlin
// settings.gradle.kts
include(":mocklane-core", ":mocklane-okhttp")
project(":mocklane-core").projectDir = file("/path/to/sdk/packages/kotlin/mocklane-core")
project(":mocklane-okhttp").projectDir = file("/path/to/sdk/packages/kotlin/mocklane-okhttp")

// app/build.gradle.kts
implementation(project(":mocklane-okhttp"))
```

## OkHttp

Interception is opt-in: `interceptor` requires an explicit `enabled` flag.
Add it **last** in the application interceptor chain, after auth/header
interceptors:

```kotlin
val client = OkHttpClient.Builder()
  .addInterceptor(authInterceptor)
  .addInterceptor(MocklaneOkHttp.interceptor(enabled = BuildConfig.DEBUG)) // last
  .build()
```

For per-client settings, pass a `MocklaneConfig`:

```kotlin
val client = OkHttpClient.Builder()
  .addInterceptor(
    MocklaneOkHttp.interceptor(
      MocklaneConfig(
        enabled = BuildConfig.DEBUG,
        failOpen = false,
        device = DeviceMetadata(deviceName = "my-app"),
      ),
    ),
  ) // last
  .build()
```

## Ktor

Use `mocklane-ktor` instead of `mocklane-okhttp`. The plugin is engine-agnostic
(CIO, OkHttp, Android, Darwin, MockEngine). Add the Ktor engine your app already
uses (`ktor-client-okhttp`, `ktor-client-android`, `ktor-client-darwin`,
`ktor-client-cio`):

```kotlin
// settings.gradle.kts
include(":mocklane-core", ":mocklane-ktor")
project(":mocklane-core").projectDir = file("/path/to/sdk/packages/kotlin/mocklane-core")
project(":mocklane-ktor").projectDir = file("/path/to/sdk/packages/kotlin/mocklane-ktor")

// app/build.gradle.kts
implementation(project(":mocklane-ktor"))
```

```kotlin
val client = HttpClient {
  install(MocklaneKtor) {
    config = MocklaneConfig(
      enabled = BuildConfig.DEBUG,
      device = DeviceMetadata(deviceName = "my-app"),
    )
  }
}
```

The plugin runs before the engine sends the request, so it sees the final URL,
query, and body content type. WebSocket handshakes and gRPC bodies are skipped.
Install it after other plugins that set request headers (for example
`WebSockets`) so those headers are visible.

## `MocklaneConfig`

| Field | Default | Meaning |
|-------|---------|---------|
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → throw |
| `probeTimeoutMs` | `150` | Fast reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |
| `enabled` | `false` | Opt-in; `true` → intercept, `false` → pass-through |

A disabled adapter stays installed but is a pass-through, so a release build
cannot accidentally enable capture.

`Mocklane.log()` uses the config of the most recently created **enabled**
adapter. Creating a disabled adapter does not clear it, so one enabled client
keeps logging while other clients stay pass-through. With no enabled adapter,
logging is a no-op. Use the same config for all clients to keep gateway and
device labels consistent.

Desktop defaults to `127.0.0.1:6625`. With `adb reverse`, that address works for
both the emulator and a physical device; **Connect Android** sets the reverse
for you. On Android 9+, the host app needs a network-security exception for
cleartext loopback — the exact `network_security_config.xml` is in
[`docs/integration/kotlin.md`](../../docs/integration/kotlin.md).

WebSocket handshakes and gRPC calls are passed through untouched until Desktop
supports them; ordinary HTTP traffic is unaffected.

Optional structured log:

```kotlin
Mocklane.log("loaded profile", tag = "home")
```

Messages are sent as-is. The JS, Dart, and Swift SDKs redact JSON log fields
(`password`, `token`, `access_token`, …), but the Kotlin/JVM SDK has no built-in
JSON parser and does not add a dependency for this, so mask secrets before
logging:

```kotlin
Mocklane.log(redactSecrets(payload))
```

## Custom adapters

For a client without an official adapter, depend on `mocklane-core` and keep
the adapter thin. The shared pieces are available under `MocklaneInternalApi`
(opt in with `@OptIn(MocklaneInternalApi::class)`):

```kotlin
@OptIn(MocklaneInternalApi::class)
class MyClientMocklane(config: MocklaneConfig) {
    private val resolved = Mocklane.bind(config)
    private val probe = HttpGatewayProbe(resolved)

    fun rewriteOrPass(url: String, headers: Map<String, String>, contentType: String?): String? {
        if (!resolved.enabled) return null
        if (UnsupportedProtocols.shouldSkip(headers["Upgrade"]?.let(::listOf).orEmpty(), contentType)) return null
        if (!probe.isReachable()) {
            if (resolved.failOpen) return null
            throw java.io.IOException(
                "Mocklane gateway unreachable at ${resolved.host}:${resolved.port}",
            )
        }
        return Rewrite.toGateway(url, resolved.host, resolved.port)
    }
}
```

Use `DeviceHeaders.values(resolved.device)` to attach the same labels, and call
`Mocklane.log` for structured logs. The shared URL-rewrite cases live in
[`../../fixtures/url-rewrite.json`](../../fixtures/url-rewrite.json).

## Sample apps

See [`../../samples/`](../../samples/) — Android / Flutter / Web demos with path
dependencies (no Maven publish required).

## Packages

Public API lives in `io.mocklane.sdk`; OkHttp adapter internals live in
`io.mocklane.sdk.internal`; Ktor adapter in `io.mocklane.sdk.ktor`.

| Type | Responsibility |
|------|----------------|
| `Mocklane` | Shared facade: `log()` + `rewrite()` |
| `MocklaneConfig` | Public runtime options |
| `DeviceMetadata` | Public device labels |
| `LogLevel` | Public log level enum |
| `MocklaneOkHttp` | OkHttp adapter facade |
| `MocklaneKtor` / `MocklaneKtorConfig` | Ktor plugin |
| `Rewrite` | Origin-prefixed gateway URL (adapter internal API) |
| `GatewayProbe` / `HttpGatewayProbe` | Reachability probe (adapter internal API) |
| `UnsupportedProtocols` / `DeviceHeaders` | Shared adapter helpers |

Only `Mocklane`, `MocklaneConfig`, `DeviceMetadata`, `LogLevel`,
`MocklaneOkHttp`, and `MocklaneKtor` are intended for app code.

## Test

```bash
cd packages/kotlin
./gradlew test
```

Runs core rewrite/config tests, OkHttp MockWebServer tests, and Ktor MockEngine
tests.

## License

MIT — see [LICENSE](../../LICENSE).
