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

  /// Shared Dio with the Mocklane interceptor installed (created on [start]).
  static Dio get dio {
    final client = _dio;
    if (client == null) {
      throw StateError('Call Mocklane.start() before using Mocklane.dio');
    }
    return client;
  }

  /// Interceptor instance for attaching to an existing Dio.
  static MocklaneInterceptor get interceptor {
    final i = _interceptor;
    if (i == null) {
      throw StateError('Call Mocklane.start() before using Mocklane.interceptor');
    }
    return i;
  }

  static bool get isActive => _interceptor != null;

  /// Enable interception toward Mocklane Desktop. Idempotent.
  static void start({
    String host = defaultGatewayHost,
    int port = defaultGatewayPort,
    bool failOpen = true,
    Duration probeTimeout = defaultProbeTimeout,
    DeviceMetadata? device,
    bool enabled = true,
    Dio? dio,
    GatewayProbe? probe,
  }) {
    stop();

    final config = MocklaneConfig(
      host: host,
      port: port,
      failOpen: failOpen,
      probeTimeout: probeTimeout,
      device: device,
      enabled: enabled,
    ).withPlatformDefaults();
    if (!config.enabled) return;

    final resolvedProbe = probe ?? HttpGatewayProbe.fromConfig(config);
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

  static void stop() {
    final client = _dio;
    final interceptor = _interceptor;
    if (client != null && interceptor != null) {
      client.interceptors.remove(interceptor);
    }
    _dio = null;
    _interceptor = null;
    _logger = null;
  }

  /// Structured log → Desktop `POST /__mocklane/v1/log`. Never throws.
  static void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    _logger?.log(message, level: level, tag: tag);
  }
}
