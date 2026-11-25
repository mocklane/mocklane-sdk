import 'dart:io';

import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

void main() {
  group('MocklaneConfig validation', () {
    test('accepts the defaults', () {
      final config = MocklaneConfig(enabled: false);
      expect(config.host, '127.0.0.1');
      expect(config.port, 6625);
      expect(config.failOpen, isTrue);
      // Opt-in: interception stays off unless the app asks for it.
      expect(config.enabled, isFalse);
    });

    test('rejects a blank host', () {
      expect(
        () => MocklaneConfig(host: '   ', enabled: false),
        throwsArgumentError,
      );
    });

    test('rejects ports outside 1..65535', () {
      expect(() => MocklaneConfig(port: 0, enabled: false), throwsRangeError);
      expect(
        () => MocklaneConfig(port: 65536, enabled: false),
        throwsRangeError,
      );
      expect(() => MocklaneConfig(port: -1, enabled: false), throwsRangeError);
    });

    test('rejects non-positive probe timeouts', () {
      expect(
        () => MocklaneConfig(probeTimeout: Duration.zero, enabled: false),
        throwsArgumentError,
      );
      expect(
        () => MocklaneConfig(
          probeTimeout: const Duration(milliseconds: -1),
          enabled: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('DeviceMetadata platform defaults', () {
    test('fills missing labels', () {
      final device =
          const DeviceMetadata(deviceName: 'my-app', appVersion: '1.2.3')
              .withPlatformDefaults();
      expect(device.deviceName, 'my-app');
      expect(device.os, Platform.operatingSystem);
      expect(device.deviceId, startsWith('${Platform.operatingSystem}:'));
      expect(device.appVersion, '1.2.3');
    });

    test('keeps complete metadata unchanged', () {
      const complete = DeviceMetadata(
        deviceId: 'id',
        deviceName: 'name',
        os: 'os',
        appVersion: '1',
      );
      final filled = complete.withPlatformDefaults();
      expect(filled.deviceId, 'id');
      expect(filled.deviceName, 'name');
      expect(filled.os, 'os');
      expect(filled.appVersion, '1');
    });

    test('platformDefault exposes OS labels and app version', () {
      final device = DeviceMetadata.platformDefault(appVersion: '9.9.9');
      expect(device.deviceId, startsWith('${Platform.operatingSystem}:'));
      expect(device.os, Platform.operatingSystem);
      expect(device.deviceName, isNotEmpty);
      expect(device.appVersion, '9.9.9');
    });
  });

  group('MocklaneConfig withPlatformDefaults', () {
    test('fills a null device', () {
      final config = MocklaneConfig(enabled: false).withPlatformDefaults();
      expect(config.device, isNotNull);
      expect(config.device!.os, Platform.operatingSystem);
      expect(config.device!.deviceId, startsWith('${Platform.operatingSystem}:'));
    });

    test('fills only the missing fields', () {
      final config =
          MocklaneConfig(
            device: const DeviceMetadata(deviceName: 'dart-app'),
            enabled: false,
          ).withPlatformDefaults();
      expect(config.device!.deviceName, 'dart-app');
      expect(config.device!.os, Platform.operatingSystem);
      expect(config.device!.deviceId, isNotNull);
    });
  });
}
