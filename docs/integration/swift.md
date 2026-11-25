# Swift (iOS / macOS)

Package: [`Mocklane`](../../packages/swift/README.md)

## Install

Add the package in Xcode (**File → Add Package Dependencies…**) or in
`Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/mocklane/mocklane-sdk.git", from: "0.1.1"),
],
targets: [
  .target(name: "MyApp", dependencies: [.product(name: "Mocklane", package: "mocklane-sdk")]),
]
```

## Minimal integration

Keep your app's session factory and decorate its configuration:

```swift
var configuration = URLSessionConfiguration.default // your app's configuration
#if DEBUG
configuration = Mocklane.intercepting(configuration, enabled: true)
#endif
let session = URLSession(configuration: configuration)
```

Use the session like any other `URLSession`:

```swift
let (data, response) = try await session.data(
  from: URL(string: "https://api.example.com/v1/me")!
)
```

`intercepting` copies the configuration, so the caller's object is unchanged
and existing `protocolClasses`, delegate, cookies, and cache keep working.

## Verify

The request appears as `GET /https://api.example.com/v1/me` in Traffic, and
`Mocklane.log("…")` appears as `SDK_LOG`.

## Advanced options

### Custom gateway

The default is `127.0.0.1:6625`. Pass a `MocklaneConfig`:

```swift
#if DEBUG
configuration = Mocklane.intercepting(
  configuration,
  config: MocklaneConfig(port: 7000, enabled: true) // or host: "192.168.1.10"
)
#endif
```

### Let Mocklane create the session

If the app does not own its session factory, `urlSession` is a convenience:

```swift
let session = Mocklane.urlSession(enabled: isDebug)
// or:
let session = Mocklane.urlSession(
  config: MocklaneConfig(port: 7000, enabled: isDebug)
)
```

### Other options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | `false` | Opt-in; set it from your build flag |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → fail |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |

Full reference: [`packages/swift/README.md`](../../packages/swift/README.md).

## Notes

- Background `URLSessionConfiguration`s are not supported: iOS rejects custom
  `URLProtocol` classes there.
- **Physical iOS:** connect over USB and run Desktop **Connect iOS** once. The
  SDK keeps `127.0.0.1`; Desktop handles the USB tunnel and reconnects after
  foreground/unlock.
