# Dart / Flutter

Package: [`mocklane`](../../packages/dart/README.md)

## Install

```bash
dart pub add mocklane       # or: flutter pub add mocklane
```

## Minimal integration

Add the interceptor to the Dio client your app already uses:

```dart
import 'package:flutter/foundation.dart';
import 'package:mocklane/mocklane.dart';

void main() {
  if (kDebugMode) {
    Mocklane.start(dio: myExistingDio);
  }
  runApp(const MyApp());
}
```

Or insert it directly, next to your other interceptors:

```dart
myExistingDio.interceptors.insert(0, Mocklane.interceptor);
```

If the app does not have a Dio client yet, `Mocklane.start()` creates one and
exposes it as `Mocklane.dio`:

```dart
Mocklane.start();
final res = await Mocklane.dio.get('https://api.example.com/v1/me');
```

## Verify

The request appears as `GET /https://api.example.com/v1/me` in Traffic, and
`Mocklane.log('…')` appears as `SDK_LOG`.

## Advanced options

### Custom gateway

The default is `127.0.0.1:6625`.

```dart
Mocklane.start(dio: myExistingDio, port: 7000);
Mocklane.start(dio: myExistingDio, host: '192.168.1.10', port: 7000);
```

### Other options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | `true` | `false` makes `start()` a no-op |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → reject |
| `probeTimeout` | `150ms` | Reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |

Full reference: [`packages/dart/README.md`](../../packages/dart/README.md).

## Physical devices

**Android:** `127.0.0.1` is the phone. Use Desktop **Connect Android** to set up
the reverse tunnel; it runs `adb reverse` for you.

**iOS:** connect over USB and run Desktop **Connect iOS** (or `mocklane connect
ios`) once. The SDK keeps `127.0.0.1`; Desktop retries the usbmux tunnel and the
SDK re-binds its listener after foreground/unlock, so the app does not need a
relaunch.
