import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.contentType,
    required this.body,
    required this.deviceId,
    required this.deviceOs,
  });

  final String method;
  final String path;
  final String? contentType;
  final String body;
  final String? deviceId;
  final String? deviceOs;
}

void main() {
  tearDown(Mocklane.stop);

  group('Mocklane facade', () {
    test('dio and interceptor throw before start', () {
      expect(() => Mocklane.dio, throwsStateError);
      expect(() => Mocklane.interceptor, throwsStateError);
    });

    test('start wires the interceptor; stop removes it', () {
      final dio = Dio();
      final before = dio.interceptors.length;

      Mocklane.start(dio: dio, probe: NeverReachableProbe());
      expect(Mocklane.isActive, isTrue);
      expect(dio.interceptors.length, before + 1);
      expect(dio.interceptors.whereType<MocklaneInterceptor>(), hasLength(1));

      Mocklane.stop();
      expect(Mocklane.isActive, isFalse);
      expect(dio.interceptors.length, before);
      expect(dio.interceptors.whereType<MocklaneInterceptor>(), isEmpty);
    });

    test('enabled:false stays inactive', () {
      Mocklane.start(enabled: false);
      expect(Mocklane.isActive, isFalse);
    });

    test('start rejects an invalid config', () {
      expect(() => Mocklane.start(host: '   '), throwsArgumentError);
      expect(() => Mocklane.start(port: 0), throwsRangeError);
      expect(
        () => Mocklane.start(probeTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(Mocklane.isActive, isFalse);
    });

    test('log is a no-op before start', () {
      expect(() => Mocklane.log('hello'), returnsNormally);
    });

    test('log posts structured JSON to the gateway when started', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final arrived = Completer<_CapturedRequest>();
      final sub = server.listen((request) async {
        final captured = _CapturedRequest(
          method: request.method,
          path: request.uri.path,
          contentType: request.headers.value('content-type'),
          body: await utf8.decoder.bind(request).join(),
          deviceId: request.headers.value('x-mocklane-device-id'),
          deviceOs: request.headers.value('x-mocklane-os'),
        );
        request.response.statusCode = 200;
        await request.response.close();
        if (!arrived.isCompleted) arrived.complete(captured);
      });

      try {
        Mocklane.start(
          host: '127.0.0.1',
          port: server.port,
          probe: AlwaysReachableProbe(),
        );
        Mocklane.log('hello', tag: 'home');

        final captured = await arrived.future.timeout(const Duration(seconds: 5));
        expect(captured.method, 'POST');
        expect(captured.path, '/__mocklane/v1/log');
        expect(captured.contentType, 'application/json');

        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['message'], 'hello');
        expect(body['tag'], 'home');
        expect(body['level'], 'info');
        // Device labels default from the platform when none are provided.
        expect(captured.deviceId, startsWith('${Platform.operatingSystem}:'));
        expect(captured.deviceOs, Platform.operatingSystem);
      } finally {
        await sub.cancel();
        await server.close();
      }
    });
  });
}
