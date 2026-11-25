import 'package:dio/dio.dart';

import 'config.dart';
import 'rewrite.dart';
import 'transport.dart';

/// Dio interceptor (SRP): rewrite absolute http(s) URIs when gateway is up.
class MocklaneInterceptor extends QueuedInterceptor {
  MocklaneInterceptor({
    required this.config,
    required this.probe,
  });

  final MocklaneConfig config;
  final GatewayProbe probe;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!config.enabled) {
      handler.next(options);
      return;
    }

    final original = options.uri.toString();
    if (!_shouldRewrite(original)) {
      handler.next(options);
      return;
    }

    final reachable = await probe.isReachable();
    if (!reachable) {
      if (config.failOpen) {
        handler.next(options);
        return;
      }
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'Mocklane gateway unreachable at ${config.host}:${config.port}',
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    final gatewayUrl = rewriteToGateway(
      original,
      host: config.host,
      port: config.port,
    );
    // Absolute URL replaces baseUrl in Dio.
    options.path = gatewayUrl;
    options.queryParameters.clear();

    _applyDeviceHeaders(options);
    handler.next(options);
  }

  bool _shouldRewrite(String url) {
    if (isGatewayUrl(url, host: config.host, port: config.port)) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  void _applyDeviceHeaders(RequestOptions options) {
    final device = config.device;
    if (device == null) return;
    if (device.deviceId != null) {
      options.headers['X-Mocklane-Device-Id'] = device.deviceId;
    }
    if (device.deviceName != null) {
      options.headers['X-Mocklane-Device-Name'] = device.deviceName;
    }
    if (device.os != null) {
      options.headers['X-Mocklane-Os'] = device.os;
    }
    if (device.appVersion != null) {
      options.headers['X-Mocklane-App-Version'] = device.appVersion;
    }
  }
}
