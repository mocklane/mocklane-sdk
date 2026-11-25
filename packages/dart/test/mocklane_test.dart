import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
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
  tearDown(Mocklane.uninstall);

  group('Mocklane facade', () {
    test('dio and interceptor throw before install', () {
      expect(() => Mocklane.dio, throwsStateError);
      expect(() => Mocklane.interceptor, throwsStateError);
    });

    test('install wires the interceptor; uninstall removes it', () {
      final dio = Dio();
      final before = dio.interceptors.length;

      Mocklane.install(dio: dio, probe: NeverReachableProbe(), enabled: true);
      expect(Mocklane.isActive, isTrue);
      expect(dio.interceptors.length, before + 1);
      expect(dio.interceptors.whereType<MocklaneInterceptor>(), hasLength(1));

      Mocklane.uninstall();
      expect(Mocklane.isActive, isFalse);
      expect(dio.interceptors.length, before);
      expect(dio.interceptors.whereType<MocklaneInterceptor>(), isEmpty);
    });

    test('enabled:false stays inactive', () {
      Mocklane.install(enabled: false);
      expect(Mocklane.isActive, isFalse);
    });

    test('disabled install leaves a running installation untouched', () {
      final dio = Dio();
      Mocklane.install(dio: dio, probe: NeverReachableProbe(), enabled: true);

      Mocklane.install(enabled: false);

      expect(Mocklane.isActive, isTrue);
      expect(dio.interceptors.whereType<MocklaneInterceptor>(), hasLength(1));
    });

    test('an invalid config is rejected before an active install is stopped',
        () {
      final dio = Dio();
      Mocklane.install(dio: dio, probe: NeverReachableProbe(), enabled: true);
      final before = dio.interceptors.length;

      expect(
        () => Mocklane.install(host: '   ', enabled: true),
        throwsArgumentError,
      );

      expect(Mocklane.isActive, isTrue);
      expect(dio.interceptors.length, before);
    });

    test('uninstall closes the probe it created, not an injected one', () {
      final injected = _CloseTrackingProbe();
      Mocklane.install(dio: Dio(), probe: injected, enabled: true);
      Mocklane.uninstall();
      expect(injected.closed, isFalse);

      final client = _TrackingClient();
      HttpGatewayProbe(
        host: '127.0.0.1',
        port: 6625,
        timeout: const Duration(milliseconds: 10),
        client: client,
      ).close();
      expect(client.closed, isTrue);
    });

    test('install rejects an invalid config', () {
      expect(
        () => Mocklane.install(host: '   ', enabled: false),
        throwsArgumentError,
      );
      expect(
        () => Mocklane.install(port: 0, enabled: false),
        throwsRangeError,
      );
      expect(
        () => Mocklane.install(probeTimeout: Duration.zero, enabled: false),
        throwsArgumentError,
      );
      expect(Mocklane.isActive, isFalse);
    });

    test('log is a no-op before install', () {
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
        Mocklane.install(
          host: '127.0.0.1',
          port: server.port,
          probe: AlwaysReachableProbe(),
          enabled: true,
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

class _CloseTrackingProbe implements GatewayProbe {
  bool closed = false;

  @override
  Future<bool> isReachable() async => true;

  @override
  void close() {
    closed = true;
  }
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('not used in this test');
  }

  @override
  void close() {
    closed = true;
  }
}
