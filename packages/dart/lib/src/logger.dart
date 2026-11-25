import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'masking.dart';

enum LogLevel { debug, info, warn, error }

abstract class LoggerTransport {
  Future<void> send({
    required String message,
    required LogLevel level,
    String? tag,
  });

  /// Release resources owned by the transport.
  void close() {}
}

class HttpLoggerTransport implements LoggerTransport {
  HttpLoggerTransport({
    required this.host,
    required this.port,
    this.device,
    http.Client? client,
    this.path = '/__mocklane/v1/log',
  }) : _client = client ?? http.Client();

  final String host;
  final int port;
  final DeviceMetadata? device;
  final String path;
  final http.Client _client;

  @override
  Future<void> send({
    required String message,
    required LogLevel level,
    String? tag,
  }) async {
    final uri = Uri.parse('http://$host:$port$path');
    final body = jsonEncode({
      'message': maskJsonString(message),
      'level': level.name,
      if (tag != null) 'tag': tag,
      'ts': DateTime.now().toUtc().toIso8601String(),
      if (device != null)
        'device': {
          if (device!.deviceId != null) 'deviceId': device!.deviceId,
          if (device!.deviceName != null) 'deviceName': device!.deviceName,
          if (device!.os != null) 'os': device!.os,
          if (device!.appVersion != null) 'appVersion': device!.appVersion,
        },
    });
    await _client.post(
      uri,
      headers: {
        'content-type': 'application/json',
        if (device?.deviceId != null) 'X-Mocklane-Device-Id': device!.deviceId!,
        if (device?.deviceName != null) 'X-Mocklane-Device-Name': device!.deviceName!,
        if (device?.os != null) 'X-Mocklane-Os': device!.os!,
        if (device?.appVersion != null) 'X-Mocklane-App-Version': device!.appVersion!,
      },
      body: body,
    );
  }

  @override
  void close() {
    _client.close();
  }
}

class Logger {
  Logger(this._transport);

  final LoggerTransport _transport;

  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    // Fail-open: never surface log errors to the host app.
    try {
      _transport.send(message: message, level: level, tag: tag).ignore();
    } catch (_) {
      // A transport that throws synchronously must not break the host app.
    }
  }

  void close() {
    _transport.close();
  }
}

extension on Future<void> {
  void ignore() {
    // ignore: unawaited_futures
    then((_) {}, onError: (_) {});
  }
}
