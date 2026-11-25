# Swift (iOS / macOS)

Package: [`Mocklane`](../../packages/swift/README.md) · Overview: [`INTEGRATION.md`](../INTEGRATION.md)

The SDK installs a `URLProtocol` into a `URLSession` configuration. While interception is enabled, the session sends every absolute `http(s)` request to `http://127.0.0.1:6625/<original-url>` instead of its original URL.

Requirements: iOS 15 or later, macOS 13 or later, Swift 5.9.

## Install

Add the package in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/mocklane/mocklane-sdk.git", from: "0.1.1"),
],
targets: [
  .target(name: "MyApp", dependencies: [.product(name: "Mocklane", package: "mocklane-sdk")]),
]
```

## Quick start

The SDK installs into the configuration your app already builds:

```swift
var configuration = URLSessionConfiguration.default // your app's configuration
#if DEBUG
configuration = Mocklane.install(configuration, enabled: true)
#endif
let session = URLSession(configuration: configuration)
```

Then use the session like any other `URLSession`:

```swift
let (data, response) = try await session.data(
  from: URL(string: "https://api.example.com/v1/me")!
)
```

`install` returns a copy of the configuration with `MocklaneURLProtocol` inserted first, so the caller's object is unchanged and existing `protocolClasses` and delegates keep working. `enabled = false` returns the configuration unchanged, which is why the call is safe inside `#if DEBUG`.

## Verify

Run the app with the Mocklane app open. The request appears as `GET /https://api.example.com/v1/me` in Traffic, and `Mocklane.log("…")` appears as an `SDK_LOG` row.

## iOS setup (App Transport Security)

The gateway is plain HTTP on loopback, which ATS blocks by default on a physical device. The app needs a debug-only exception in `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

`NSAllowsLocalNetworking` covers loopback and local-network hosts without weakening ATS for public hosts. If your project still reports an ATS error (iOS 17 and later, with some device or proxy combinations), allow arbitrary loads **only in a Debug `.xcconfig` or `Info.plist`**, never in a release build:

```xml
<key>NSAllowsArbitraryLoads</key>
<true/>
```

Alternatively, list each debug-only host under `NSExceptionDomains` with `NSExceptionAllowsInsecureHTTPLoads`.

## Physical iOS

Connect the device over USB and run **Connect iOS** in the Mocklane app once. The SDK keeps `127.0.0.1`; the Mocklane app maintains the USB tunnel and reconnects after foreground/unlock.

The USB bridge listens on loopback without authentication. Anything on the device that can reach loopback can forward traffic through it, so treat it as a debug-only trust boundary and never enable interception in a release build.

## Advanced

### Custom gateway

The default is `127.0.0.1:6625`. Pass a `MocklaneConfig`:

```swift
#if DEBUG
configuration = Mocklane.install(
  configuration,
  config: MocklaneConfig(port: 7000, enabled: true) // or host: "192.168.1.10"
)
#endif
```

### Let Mocklane create the session

If the app does not own its session factory, `urlSession` returns a configured session:

```swift
#if DEBUG
let session = Mocklane.urlSession(enabled: true)
#else
let session = URLSession(configuration: .default)
#endif
```

For per-client settings, pass a `MocklaneConfig`:

```swift
#if DEBUG
let session = Mocklane.urlSession(
  config: MocklaneConfig(port: 7000, enabled: true)
)
#endif
```

The app should create the session once and reuse it. Both `urlSession` overloads also accept a `URLSessionDelegate` and delegate queue, like the `URLSession` initializer.

### Options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | — (required) | Pass your build flag; `true` → intercept, `false` → pass-through |
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → fail |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Device labels in Traffic |

Full reference: [`packages/swift/README.md`](../../packages/swift/README.md).

### Local checkout

For SDK development, point the app at the package directory instead of the GitHub tag:

```swift
// Package.swift
.package(path: "<path-to-sdk>/packages/swift")
```

### Behavior notes

- Cookies are read from and stored in the configuration's `HTTPCookieStorage` against the original origin; the URL cache is bypassed for intercepted requests so every call reaches the gateway.
- Background `URLSessionConfiguration`s are not supported: iOS rejects custom `URLProtocol` classes there.
- Invalid config values do not crash the app. A blank or malformed `host`, an out-of-range `port`, or a non-positive `probeTimeoutMs` falls back to the default, with the reason in `config.validationError`; a bad host or port also forces `enabled = false`. Bare IPv6 hosts are bracketed automatically.
- A disabled config is a no-op for an already enabled session: interception stays active and the `Mocklane.log` runtime is unchanged.

## Logging and privacy

`Mocklane.log(message, level: …, tag: …)` posts the message to the gateway, and the Mocklane app stores the captured traffic. Masking is best-effort and applies only to the log message. A message is scanned only when it is valid JSON, and only the keys `password`, `token`, `access_token`, `refresh_token`, `id_token`, `secret`, `client_secret`, `api_key`, `session`, and `session_id` are replaced. The tag and free text are not scanned. Request and response bodies are never redacted.

The gateway is plain HTTP without authentication. The `host` setting must stay on loopback (`127.0.0.1`); pointing it at a LAN address sends captured credentials to everyone on that network.
