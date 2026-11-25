# mocklane (Swift)

Debug-only HTTP interceptor for **URLSession**. Same gateway contract as JS/Dart/Kotlin:

`https://api.example.com/v1/x` → `http://127.0.0.1:6625/https://api.example.com/v1/x`

Fail-open if Desktop is down. Gate with `#if DEBUG` in the host app.

## Install (Swift Package Manager)

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/mocklane/mocklane-sdk.git", from: "0.1.1"),
],
targets: [
  .target(name: "MyApp", dependencies: [.product(name: "Mocklane", package: "mocklane-sdk")]),
]
```

Xcode: **File → Add Package Dependencies…** → `https://github.com/mocklane/mocklane-sdk.git`.

SPM resolves the package by git URL, so `Package.swift` also lives at the repo
root and points at the sources here.

## Integration

Interception is opt-in: pass an explicit `enabled` flag.

### Add Mocklane to your existing session

If the app owns its `URLSession` factory, decorate the configuration and create
the session as usual. Mocklane stays one layer among your existing protocols,
delegate, cookies, and cache:

```swift
var configuration = URLSessionConfiguration.default // your app's configuration
if isDebug {
  configuration = Mocklane.intercepting(configuration, enabled: true)
}
let session = URLSession(
  configuration: configuration,
  delegate: apiClientDelegate,
  delegateQueue: apiClientDelegateQueue
)
```

`intercepting` copies the configuration (the caller's object is unchanged) and
inserts `MocklaneURLProtocol` first, so other protocol classes keep working. A
disabled config is returned unchanged.

To use a custom gateway port (default `6625`), pass a `MocklaneConfig`:

```swift
let config = MocklaneConfig(port: 7000, enabled: isDebug)
configuration = Mocklane.intercepting(configuration, config: config)
```

`MocklaneConfig` carries every option (host, port, fail-open, probe timeout,
device labels); new options are added there without changing this call.

### Convenience: let Mocklane create the session

Pass your build flag directly:

```swift
let session = Mocklane.urlSession(enabled: isDebug)

let (data, response) = try await session.data(
  from: URL(string: "https://api.example.com/v1/me")!
)
```

For per-client settings, pass a `MocklaneConfig`:

```swift
let session = Mocklane.urlSession(
  config: MocklaneConfig(
    enabled: isDebug,
    failOpen: false,
    device: DeviceMetadata(deviceName: "my-app")
  )
)
```

`MocklaneConfig` fields:

| Field | Default | Meaning |
|-------|---------|---------|
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → fail |
| `probeTimeoutMs` | `150` | Fast reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |
| `enabled` | `false` | Opt-in; `true` → intercept, `false` → pass-through / no logs |

Create the session once and reuse it. A disabled config returns a plain
`URLSession`, so a release build cannot accidentally enable capture. Existing
enabled sessions keep intercepting.

Both overloads also accept a `URLSessionDelegate` and delegate queue, the same
as `URLSession(configuration:delegate:delegateQueue:)`. The SDK never sees the
delegate's callbacks.

`Mocklane.log()` reuses the config of the most recently created enabled session.
If that session is disabled, or no session has been created, logging is a no-op.
Use the same config for all sessions to keep gateway and device labels
consistent.

Desktop defaults to `127.0.0.1:6625`. On the Simulator or macOS that is already
the local gateway; physical iOS also starts the embedded USB mux automatically
when the session is created on a loopback host. The bridge listens on loopback
only, so it is never reachable from the local network.

### Behavior

- **Streaming** — response bodies are forwarded chunk by chunk, so SSE and
  long-poll responses reach the app as they arrive. Cancelling the task stops
  the forwarded request.
- **Cookies** — a custom `URLProtocol` bypasses URLSession's cookie handling, so
  the SDK mirrors it: it attaches `Cookie` from your configuration's
  `HTTPCookieStorage` and stores `Set-Cookie` against the original origin.
- **Redirects** — followed inside the forwarding session and captured, including
  relative `Location` headers resolved against the original origin.
- **Configuration** — the session you pass in is copied; the SDK does not mutate
  your `URLSessionConfiguration`.
- **Background sessions are not supported** — iOS rejects custom `URLProtocol`
  classes in background configurations, so `urlSession(enabled: true, …)` traps
  if `configuration.identifier` is set. Pass-through (`enabled: false`) is fine.
- **Uploads** — Desktop buffers request bodies up to 64 MiB
  (`GATEWAY_REQUEST_BODY_MAX`); larger uploads fail at the gateway. Response
  streaming is unaffected.

WebSocket handshakes and gRPC calls are passed through untouched until Desktop
supports them; ordinary HTTP traffic is unaffected.

Optional structured log:

```swift
Mocklane.log("loaded profile", tag: "home")
```

## Sample apps

See [`../../samples/ios/`](../../samples/ios/) (SwiftUI) and
[`../../samples/swift-cli/`](../../samples/swift-cli/) (macOS CLI).

## Packages

Public API lives in `Mocklane`, `MocklaneConfig`, `DeviceMetadata`, and
`LogLevel`. Everything else is internal.

| Type | Responsibility |
|------|----------------|
| `Mocklane` | Public facade: `urlSession(enabled/config)` + `log()` |
| `MocklaneConfig` | Public runtime options |
| `DeviceMetadata` | Public device labels |
| `LogLevel` | Public log level enum |
| `MocklaneURLProtocol` | URLSession hook: probes, rewrites, streams back |
| `Forwarder` | Long-lived forwarding session per runtime (streaming, redirects, cookies, cancel) |
| `MocklaneRewrite` | Origin-prefixed gateway URL |
| `GatewayProbe` | Reachability probe (URLSession) |
| `Logger` | `POST /__mocklane/v1/log` |
| `Masking` | Redaction helpers applied to `Logger` messages |

## Test

```bash
cd packages/swift
swift test
```

## License

MIT — see [LICENSE](../../LICENSE).
