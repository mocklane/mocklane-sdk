# Mocklane SDK

Debug-only HTTP interception for JavaScript, Dart/Flutter, Swift, and Kotlin apps.
The SDK routes your app's HTTP through **Mocklane Desktop**, so requests show up
in Traffic and can be mocked, rewritten, or paused — without changing `BASE_URL`
or adding an in-app mock engine.

```text
App HTTP → Mocklane SDK → http://127.0.0.1:6625/<origin>/<path> → Mocklane Desktop
                        ↘ fail-open to the original URL when Desktop is unreachable
```

Interception is opt-in in every SDK. Enable it only in debug builds.

## Packages

| Platform | HTTP client | Package | Install |
|----------|-------------|---------|---------|
| JavaScript / TypeScript (Node 18+) | `fetch` | [`mocklane-sdk`](packages/js/README.md) | `npm i -D mocklane-sdk` |
| Dart / Flutter (Dart 3.3+) | Dio | [`mocklane`](packages/dart/README.md) | `dart pub add mocklane` |
| Swift (iOS 15+, macOS 13+) | `URLSession` | [`Mocklane`](packages/swift/README.md) | SPM: `https://github.com/mocklane/mocklane-sdk.git`, from `0.1.1` |
| Kotlin / Android / JVM (JDK 17) | OkHttp, Ktor | [`io.github.mocklane:mocklane-okhttp`](packages/kotlin/README.md) / `mocklane-ktor` | `debugImplementation("io.github.mocklane:mocklane-okhttp:0.1.1")` |

## Quick start

```ts
// JavaScript / TypeScript
import { Mocklane } from 'mocklane-sdk';
Mocklane.start();
```

```dart
// Dart / Flutter — add to your existing Dio
import 'package:mocklane/mocklane.dart';
Mocklane.start(dio: myDio); // or Mocklane.start() and use Mocklane.dio
```

```swift
// Swift — decorate your existing session configuration
let configuration = Mocklane.intercepting(.default, enabled: isDebug)
let session = URLSession(configuration: configuration)
```

```kotlin
// Kotlin (OkHttp)
val client = OkHttpClient.Builder()
  .addInterceptor(MocklaneOkHttp.interceptor(enabled = BuildConfig.DEBUG))
  .build()
```

Per-platform setup, configuration, and device connectivity:
[`docs/integration.md`](docs/integration.md).

## Repository layout

```text
packages/     # one directory per platform SDK
samples/      # runnable demo apps (web, Android, Flutter, iOS, Swift CLI)
fixtures/     # shared URL-rewrite test cases
docs/         # integration, testing, publishing
scripts/      # sample generation and the web E2E test
```

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/integration.md`](docs/integration.md) | Integrate the SDK into an app and connect it to Desktop |
| [`docs/testing.md`](docs/testing.md) | Unit tests, CI, and the web end-to-end test |
| [`docs/publishing.md`](docs/publishing.md) | Release and publish the four packages |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Branch, merge-request, and verification workflow |
| [`samples/README.md`](samples/README.md) | Runnable samples and the shared scenario catalog |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## Gateway contract

Reserved path:

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/__mocklane/v1/log` | Structured logs from `Mocklane.log` |

Optional device headers: `X-Mocklane-Device-Id`, `X-Mocklane-Device-Name`,
`X-Mocklane-Os`, `X-Mocklane-App-Version`.

The SDK only rewrites absolute `http(s)` URLs. Relative URLs have no origin to
embed and pass through unchanged.

## License

MIT — see [LICENSE](LICENSE).
