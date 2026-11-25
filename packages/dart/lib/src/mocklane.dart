import 'package:dio/dio.dart';

import 'config.dart';
import 'interceptor.dart';
import 'logger.dart';
import 'transport.dart';

/// Composition root — wires config → probe → Dio interceptor → logger.
class Mocklane {
  Mocklane._();

  static MocklaneInterceptor? _interceptor;
  static Logger? _logger;
  static Dio? _dio;
  static GatewayProbe? _probe;
  static bool _ownsProbe = false;

  /// Shared Dio with the Mocklane interceptor installed (created on [install]).
  static Dio get dio {
    final client = _dio;
    if (client == null) {
      throw StateError('Call Mocklane.install() before using Mocklane.dio');
    }
    return client;
  }

  /// Interceptor instance for attaching to an existing Dio.
  static MocklaneInterceptor get interceptor {
    final i = _interceptor;
    if (i == null) {
      throw StateError('Call Mocklane.install() before using Mocklane.interceptor');
    }
    return i;
  }

  static bool get isActive => _interceptor != null;

  /// Enable interception toward Mocklane Desktop. Idempotent.
  ///
  /// [enabled] is required and has no default, so pass your build flag. A
  /// disabled call is a no-op and leaves any running installation untouched.
  /// Config is validated before anything is torn down, so invalid options
  /// throw without stopping an active installation.
  static void install({
    String host = defaultGatewayHost,
    int port = defaultGatewayPort,
    bool failOpen = true,
    Duration probeTimeout = defaultProbeTimeout,
    DeviceMetadata? device,
    required bool enabled,
    Dio? dio,
    GatewayProbe? probe,
  }) {
    final config = MocklaneConfig(
      host: host,
      port: port,
      failOpen: failOpen,
      probeTimeout: probeTimeout,
      device: device,
      enabled: enabled,
    ).withPlatformDefaults();
    if (!config.enabled) return;

    uninstall();

    final resolvedProbe = probe ?? HttpGatewayProbe.fromConfig(config);
    _probe = resolvedProbe;
    _ownsProbe = probe == null;
    _interceptor = MocklaneInterceptor(config: config, probe: resolvedProbe);
    _logger = Logger(
      HttpLoggerTransport(
        host: config.host,
        port: config.port,
        device: config.device,
      ),
    );

    final client = dio ?? Dio();
    client.interceptors.insert(0, _interceptor!);
    _dio = client;
  }

  /// Removes the interceptor from the client it was installed on and releases
  /// the transports Mocklane created (injected probes stay caller-owned).
  static void uninstall() {
    final client = _dio;
    final interceptor = _interceptor;
    if (client != null && interceptor != null) {
      client.interceptors.remove(interceptor);
    }
    _logger?.close();
    if (_ownsProbe) {
      _probe?.close();
    }
    _dio = null;
    _interceptor = null;
    _logger = null;
    _probe = null;
    _ownsProbe = false;
  }

  /// Structured log → Desktop `POST /__mocklane/v1/log`. Never throws.
  static void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    _logger?.log(message, level: level, tag: tag);
  }
}
