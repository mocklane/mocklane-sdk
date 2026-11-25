# mocklane (Dart / Flutter)

Debug-only HTTP interceptor. Rewrites absolute URLs through Mocklane Desktop:

`https://api.example.com/v1/x` → `http://127.0.0.1:6625/https://api.example.com/v1/x`

Fail-open if Desktop is down. Gate behind `kDebugMode` in Flutter release builds.

## Install

```bash
dart pub add mocklane
# or, in a Flutter app:
flutter pub add mocklane
```

```dart
import 'package:mocklane/mocklane.dart';

void main() {
  Mocklane.start(); // attaches a Dio interceptor via Mocklane.dio
  runApp(MyApp());
}

// Prefer: use the shared Dio
final dio = Mocklane.dio;
```

Or attach to an existing client:

```dart
dio.interceptors.insert(0, Mocklane.interceptor);
```

Device labels for Desktop Traffic default from the platform
(`Platform.operatingSystem`, plus the hostname on desktop). Override any field:

```dart
Mocklane.start(
  device: const DeviceMetadata(deviceName: 'my-app', appVersion: '1.2.3'),
);
```

Config is validated when the interceptor is created: a blank host, a port
outside 1–65535, or a non-positive probe timeout throws from `Mocklane.start()`.

## License

MIT — see [LICENSE](LICENSE).
