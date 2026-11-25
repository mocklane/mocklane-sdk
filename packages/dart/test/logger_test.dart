import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocklane/mocklane.dart';
import 'package:mocklane/src/logger.dart';
import 'package:test/test.dart';

void main() {
  group('HttpLoggerTransport', () {
    test('posts masked structured JSON with device headers', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('ok', 200);
      });

      final transport = HttpLoggerTransport(
        host: '127.0.0.1',
        port: 6625,
        device: const DeviceMetadata(deviceId: 'dart-test', deviceName: 'dart-log'),
        client: client,
      );

      await transport.send(
        message: '{"user":"a","password":"hunter2"}',
        level: LogLevel.warn,
        tag: 'home',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://127.0.0.1:6625/__mocklane/v1/log');
      expect(captured.headers['content-type'], 'application/json');
      expect(captured.headers['X-Mocklane-Device-Id'], 'dart-test');
      expect(captured.headers['X-Mocklane-Device-Name'], 'dart-log');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['message'], '{"user":"a","password":"[REDACTED]"}');
      expect(body['level'], 'warn');
      expect(body['tag'], 'home');
      expect((body['device'] as Map<String, dynamic>)['deviceId'], 'dart-test');
      expect((body['device'] as Map<String, dynamic>)['deviceName'], 'dart-log');
    });

    test('leaves non-JSON messages unchanged', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('ok', 200);
      });

      final transport = HttpLoggerTransport(
        host: '127.0.0.1',
        port: 6625,
        client: client,
      );

      await transport.send(message: 'plain text', level: LogLevel.info);

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['message'], 'plain text');
    });
  });

  group('Logger', () {
    test('never throws when the transport fails', () async {
      final logger = Logger(_ThrowingTransport());
      expect(() => logger.log('hello'), returnsNormally);
      // Give the swallowed future a turn to surface, if it would.
      await Future<void>.delayed(Duration.zero);
    });

    test('forwards message, level, and tag', () async {
      final transport = _CapturingTransport();
      Logger(transport).log('hi', level: LogLevel.error, tag: 'home');
      await Future<void>.delayed(Duration.zero);
      expect(transport.last, ('hi', LogLevel.error, 'home'));
    });
  });
}

class _ThrowingTransport implements LoggerTransport {
  @override
  Future<void> send({
    required String message,
    required LogLevel level,
    String? tag,
  }) async {
    throw StateError('down');
  }
}

class _CapturingTransport implements LoggerTransport {
  (String, LogLevel, String?)? last;

  @override
  Future<void> send({
    required String message,
    required LogLevel level,
    String? tag,
  }) async {
    last = (message, level, tag);
  }
}
