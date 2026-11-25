# Samples

Runnable reference apps that integrate the SDK packages. Every sample runs the same scenario catalog from [`scenarios.json`](scenarios.json).

| Sample | Stack | Integration entry point | How to run |
|--------|-------|-------------------------|------------|
| [`web/`](web/) | Vite + fetch | [`web/src/bootstrap.js`](web/src/bootstrap.js) | `pnpm --filter mocklane-web-demo dev` |
| [`android/`](android/) | OkHttp | [`android/.../integration/MocklaneBootstrap.kt`](android/app/src/main/java/io/mocklane/sample/integration/MocklaneBootstrap.kt) | `./gradlew :app:assembleDebug` |
| [`flutter/`](flutter/) | Dio | [`flutter/lib/bootstrap.dart`](flutter/lib/bootstrap.dart) | `flutter run` |
| [`ios/`](ios/) | URLSession + SwiftUI | [`ios/App/MocklaneIOSSampleApp.swift`](ios/App/MocklaneIOSSampleApp.swift) | Xcode / `xcodegen generate` |
| [`swift-cli/`](swift-cli/) | URLSession CLI | [`swift-cli/Sources/MocklaneSwiftSampleApp.swift`](swift-cli/Sources/MocklaneSwiftSampleApp.swift) | `swift run` |

## Prerequisites

1. Mocklane app running — status **Listening :6625**, Traffic open.
2. Internet access (samples call `postman-echo.com` and `jsonplaceholder.typicode.com`).
3. `pnpm install` at the repository root.

## Scenario catalog

| ID | Kind | Summary |
|----|------|---------|
| S01 | API | GET + query (`postman-echo.com/get`) |
| S02 | API | POST JSON |
| S03 | API | PUT JSON |
| S04 | API | PATCH JSON |
| S05 | API | DELETE |
| S06 | API | Form POST (`x-www-form-urlencoded`) |
| S07 | API | GET with an `Authorization` header |
| S08 | API | GET JSON resource (`jsonplaceholder.typicode.com/posts/1`) |
| S09 | API | GET binary bytes (256) |
| S10 | API | GET gzip binary |
| S11 | API | GET slow 2s (`/delay/2`) |
| S12 | API | GET HTTP 404 (`/status/404`) |
| L01 | SDK log | `Mocklane.log` info / `ui` tag |
| L02 | SDK log | `Mocklane.log` warn / `network` tag |

### How scenarios reach each sample

```text
samples/scenarios.json
        │
        ├─► web: imported directly by src/scenarios.js
        │
        └─► pnpm generate:samples
              ├─► android/.../demo/DemoScenarios.kt
              ├─► ios/App/DemoScenarios.swift
              ├─► flutter/lib/demo_scenarios.dart
              └─► swift-cli/Sources/DemoScenarios.swift
```

The generated `DemoScenarios.*` files are not edited by hand. If you edit [`scenarios.json`](scenarios.json), regenerate with `pnpm generate:samples` and commit the regenerated files.

## UI

Every GUI sample provides:

- Scrollable list of scenarios (`S01`–`S12`, `L01`–`L02`)
- Per-row **Run**, footer **Run all** and **Clear output**
- Monospace output panel (status, truncated body or byte count)

## Expected Traffic (Run all)

| Scenario | Mocklane app row |
|----------|-------------|
| S01–S12 | `FORWARD` with matching method + path suffix |
| L01, L02 | `SDK_LOG` `POST /__mocklane/v1/log` |

## Device networking

| Client | Gateway host |
|--------|--------------|
| Web / macOS / iOS Simulator | `127.0.0.1` (default) |
| Android emulator | `127.0.0.1` via Connect Android / `adb reverse` |
| Physical Android / iOS | **Connect Android** / **Connect iOS** |

## E2E (web Run all)

```bash
# Terminal A: Mocklane app, or `mocklane serve`
# Terminal B:
pnpm install && pnpm --filter mocklane-sdk build && pnpm --filter mocklane-web-demo dev
# Terminal C:
MOCKLANE_BIN=/path/to/mocklane pnpm e2e:web-demo
```

See [`docs/testing.md`](../docs/testing.md) and [`docs/integration.md`](../docs/integration.md).
