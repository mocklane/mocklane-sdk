# Dart / Flutter

Package: [`mocklane`](../../packages/dart/README.md) · Overview: [`INTEGRATION.md`](../INTEGRATION.md)

The SDK attaches a Dio interceptor. While interception is enabled, it sends every absolute `http(s)` request to `http://127.0.0.1:6625/<original-url>` instead of its original URL. Relative URLs pass through untouched.

Requirements: Dart 3.3 or later and Dio 5.7 or later.

## Install

```bash
dart pub add mocklane       # or: flutter pub add mocklane
```

## Quick start

Install Mocklane into the Dio client your app already uses:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mocklane/mocklane.dart';

final dio = Dio(); // your app's existing HTTP client

void main() {
  Mocklane.install(dio: dio, enabled: kDebugMode);
  runApp(const MyApp());
}
```

If the app has no Dio client yet, let Mocklane create and own one:

```dart
Mocklane.install(enabled: true);

final res = await Mocklane.dio.get('https://api.example.com/v1/me');
```

To attach the same interceptor to additional Dio instances, insert it into each client after `install()`:

```dart
otherDio.interceptors.insert(0, Mocklane.interceptor);
```

`enabled` is required and has no default: pass your build flag. A disabled `Mocklane.install()` is a no-op: it leaves a running installation untouched, and an invalid config throws before anything is stopped.

## Verify

Run the app with the Mocklane app open. The request appears as `GET /https://api.example.com/v1/me` in Traffic, and `Mocklane.log('…')` appears as an `SDK_LOG` row.

## Devices

**Android:** `127.0.0.1` refers to the phone. Use **Connect Android** in the Mocklane app once; it runs `adb reverse` so the phone's loopback reaches your computer.

**iOS:** connect over USB and run **Connect iOS** in the Mocklane app (or `mocklane connect ios`) once. The SDK keeps `127.0.0.1`; the Mocklane app maintains the usbmux tunnel and reconnects after foreground/unlock, so the app does not need a relaunch.

## Advanced

### Custom gateway

The default is `127.0.0.1:6625`. Override the port, or the host as well:

```dart
Mocklane.install(dio: dio, enabled: true, port: 7000);
// or:
Mocklane.install(dio: dio, enabled: true, host: '192.168.1.10', port: 7000);
```

### Options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | — (required) | Pass your build flag; `false` makes `install()` a no-op |
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → reject |
| `probeTimeout` | `150ms` | Reachability-probe timeout |
| `device` | platform default | Device labels in Traffic |

Full reference: [`packages/dart/README.md`](../../packages/dart/README.md).

### Lifecycle

`Mocklane.uninstall()` removes the interceptor from the client it was installed on. `Mocklane.isActive` reports whether an installation is active.

```dart
Mocklane.uninstall();
print(Mocklane.isActive); // false
```

### Local checkout

For SDK development, point the app at the package directory instead of pub.dev:

```yaml
# pubspec.yaml
dependencies:
  mocklane:
    path: <path-to-sdk>/packages/dart
```

### Cookie managers

Dio cookie managers (`dio_cookie_manager`) key cookies by request URL. The SDK inserts its interceptor first and rewrites the URL to the gateway host before the cookie manager runs, so cookies are stored under `127.0.0.1:6625` instead of your origin and are not shared with clients that skip Mocklane. Auth that depends on origin-scoped cookies may therefore behave differently while interception is on.

## Logging and privacy

`Mocklane.log(message, level: …, tag: …)` posts the message to the gateway, and the Mocklane app stores the captured traffic. Masking is best-effort and applies only to the log message. A message is scanned only when it is valid JSON, and only the keys `password`, `token`, `access_token`, `refresh_token`, `id_token`, `secret`, `client_secret`, `api_key`, `session`, and `session_id` are replaced. The tag and free text are not scanned. Request and response bodies are never redacted.

The gateway is plain HTTP without authentication. The `host` setting must stay on loopback (`127.0.0.1`); pointing it at a LAN address sends captured credentials to everyone on that network.
