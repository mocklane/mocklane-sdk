// Immutable runtime options.

import 'dart:math';

import 'platform_defaults_web.dart'
    if (dart.library.io) 'platform_defaults_io.dart';

const String defaultGatewayHost = '127.0.0.1';
const int defaultGatewayPort = 6625;
const Duration defaultProbeTimeout = Duration(milliseconds: 150);

final Random _random = Random();

class DeviceMetadata {
  const DeviceMetadata({
    this.deviceId,
    this.deviceName,
    this.os,
    this.appVersion,
  });

  final String? deviceId;
  final String? deviceName;
  final String? os;
  final String? appVersion;

  /// Fill missing fields from [platformDefault] so Traffic can group by a
  /// stable id without every app inventing labels.
  DeviceMetadata withPlatformDefaults({String? appVersion}) {
    final base =
        DeviceMetadata.platformDefault(appVersion: appVersion ?? this.appVersion);
    return DeviceMetadata(
      deviceId: deviceId ?? base.deviceId,
      deviceName: deviceName ?? base.deviceName,
      os: os ?? base.os,
      appVersion: this.appVersion ?? base.appVersion,
    );
  }

  /// Best-effort identity for the current platform.
  ///
  /// Uses `Platform.operatingSystem` on dart:io runtimes (Android, iOS,
  /// desktop) and `web` in browsers. The id is per-runtime; pass an explicit
  /// [deviceId] when a stable id across restarts matters.
  static DeviceMetadata platformDefault({String? appVersion}) {
    final labels = platformDefaultLabels();
    final os = labels['os']!;
    return DeviceMetadata(
      deviceId: '$os:${_randomToken()}',
      deviceName: labels['deviceName'],
      os: os,
      appVersion: appVersion,
    );
  }
}

String _randomToken() {
  final bytes = List<int>.generate(4, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class MocklaneConfig {
  factory MocklaneConfig({
    String host = defaultGatewayHost,
    int port = defaultGatewayPort,
    bool failOpen = true,
    Duration probeTimeout = defaultProbeTimeout,
    DeviceMetadata? device,
    required bool enabled,
  }) {
    if (host.trim().isEmpty) {
      throw ArgumentError.value(host, 'host', 'must not be blank');
    }
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (probeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        probeTimeout,
        'probeTimeout',
        'must be greater than zero',
      );
    }
    return MocklaneConfig._(
      host: host,
      port: port,
      failOpen: failOpen,
      probeTimeout: probeTimeout,
      device: device,
      enabled: enabled,
    );
  }

  const MocklaneConfig._({
    required this.host,
    required this.port,
    required this.failOpen,
    required this.probeTimeout,
    required this.device,
    required this.enabled,
  });

  final String host;
  final int port;
  final bool failOpen;
  final Duration probeTimeout;
  final DeviceMetadata? device;

  /// Opt-in switch; required, with no default. A disabled `Mocklane.install()`
  /// is a no-op and leaves any running installation untouched.
  final bool enabled;

  /// Fill missing device labels from the current platform.
  MocklaneConfig withPlatformDefaults() {
    final current = device;
    if (current?.deviceId != null &&
        current?.deviceName != null &&
        current?.os != null) {
      return this;
    }
    return MocklaneConfig(
      host: host,
      port: port,
      failOpen: failOpen,
      probeTimeout: probeTimeout,
      device: (current ?? const DeviceMetadata()).withPlatformDefaults(),
      enabled: enabled,
    );
  }
}
