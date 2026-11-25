import 'package:mocklane/mocklane.dart';

/// Minimal example. Run with Mocklane Desktop listening on port 6625:
///
///     dart run example/main.dart
void main() {
  Mocklane.install(
    enabled: true,
    device: const DeviceMetadata(deviceName: 'dart-example'),
  );

  print(
    'Rewritten: '
    '${rewriteToGateway('https://api.example.com/v1/me')}',
  );

  // Route requests through the shared Dio so Desktop sees them in Traffic.
  // final response = await Mocklane.dio.get('https://api.example.com/v1/me');

  Mocklane.log('example started', tag: 'example');

  Mocklane.uninstall();
}
