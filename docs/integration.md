# Integrate the SDK

Mocklane sits inside the HTTP stack your app already uses — add it alongside
auth, logging, and other client layers rather than replacing the client.

```text
Your app → Mocklane SDK → http://127.0.0.1:6625/<real-origin>/...
                                  ↓
                          Mocklane Desktop (Traffic)
                                  ↓
                             real API (or mock)
```

## Prerequisites

1. Run **Mocklane Desktop** and confirm the gateway is listening. The default
   address is **`127.0.0.1:6625`**; if you use a different port, set it in the
   SDK config (each platform guide shows how).
2. Make requests with **absolute** `http(s)` URLs. Relative paths (`/v1/me`)
   are not rewritten because there is no origin to embed.
3. Install the SDK for your platform from the guide below.

## Choose your platform

| Platform | HTTP client | Guide |
|----------|-------------|-------|
| JavaScript / TypeScript | `fetch` | [`integration/javascript.md`](integration/javascript.md) |
| Dart / Flutter | Dio | [`integration/dart.md`](integration/dart.md) |
| Kotlin / Android / JVM | OkHttp, Ktor | [`integration/kotlin.md`](integration/kotlin.md) |
| Swift (iOS / macOS) | `URLSession` | [`integration/swift.md`](integration/swift.md) |

## What success looks like in Desktop

| Action in the app | Traffic row | Mode |
|-------------------|-------------|------|
| `fetch` / `dio.get('https://…')` | `GET /https://host/path` | `FORWARD` (or `MOCK` / `BREAK` with a rule) |
| `Mocklane.log('…')` | `POST /__mocklane/v1/log` | `SDK_LOG` |
| Device metadata | Detail / source | `source_label` = device name |

## Common pitfalls

| Symptom | Cause |
|---------|-------|
| No Traffic at all | Desktop is not listening on the configured port, or the SDK is not enabled |
| Traffic empty but the API works | Fail-open: Desktop is down or unreachable → original URL used |
| Relative URL never appears | Only absolute `http(s)://…` URLs are rewritten |
| Phone works but no capture | The phone's `127.0.0.1` is not your Mac; use Connect Android / Connect iOS |
| `SDK_LOG` missing | Desktop must support `POST /__mocklane/v1/log` |

## Using a local checkout

For SDK development, point your app at the package directory instead of a
registry. Replace `<path-to-sdk>` with the repository checkout path.

```bash
# npm
pnpm add mocklane-sdk@file:<path-to-sdk>/packages/js
```

```yaml
# pubspec.yaml
dependencies:
  mocklane:
    path: <path-to-sdk>/packages/dart
```

```kotlin
// settings.gradle.kts
include(":mocklane-core", ":mocklane-okhttp")
project(":mocklane-core").projectDir = file("<path-to-sdk>/packages/kotlin/mocklane-core")
project(":mocklane-okhttp").projectDir = file("<path-to-sdk>/packages/kotlin/mocklane-okhttp")
```

```swift
// Package.swift
.package(path: "<path-to-sdk>/packages/swift")
```
