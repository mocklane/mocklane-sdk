import 'package:flutter/foundation.dart';
import 'package:mocklane/mocklane.dart';

/// Mocklane integration for debug builds.
/// See ../../../docs/integration.md.
class MocklaneBootstrap {
  static bool get isEnabled => kDebugMode;

  static String gatewayHost() {
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
  }

  static void install() {
    if (!isEnabled) return;
    Mocklane.install(
      enabled: isEnabled,
      host: gatewayHost(),
      device: const DeviceMetadata(
        deviceName: 'flutter-sample',
        os: 'flutter',
        appVersion: '0.1.1',
      ),
    );
  }

  static void uninstall() {
    if (!isEnabled) return;
    Mocklane.uninstall();
  }
}
