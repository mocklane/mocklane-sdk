import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Mocklane.uninstall);

  test('rewrites when gateway reachable', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    Mocklane.install(
      dio: dio,
      probe: AlwaysReachableProbe(),
      enabled: true,
      device: const DeviceMetadata(deviceName: 'test-device'),
    );

    try {
      await dio.get('https://api.example.com/v1/me');
    } catch (_) {
      // adapter returns empty; may throw on decode — we only care about URL
    }

    expect(
      adapter.lastUri.toString(),
      'http://127.0.0.1:6625/https://api.example.com/v1/me',
    );
    final headers = adapter.lastHeaders!;
    expect(
      headers['X-Mocklane-Device-Name'] ?? headers['x-mocklane-device-name'],
      'test-device',
    );
  });

  test('fail-opens when gateway down', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    Mocklane.install(dio: dio, probe: NeverReachableProbe(), enabled: true);

    try {
      await dio.get('https://api.example.com/v1/me');
    } catch (_) {}

    expect(adapter.lastUri.toString(), 'https://api.example.com/v1/me');
  });

  test('enabled:false is a no-op', () {
    Mocklane.install(enabled: false);
    expect(Mocklane.isActive, isFalse);
  });

  test('concurrent requests are not serialised behind the probe', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final probe = _GatedProbe();
    Mocklane.install(dio: dio, probe: probe, enabled: true);

    final first = dio.get('https://api.example.com/a');
    final second = dio.get('https://api.example.com/b');
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (probe.calls < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Both requests reached the probe while it was still pending: a
    // QueuedInterceptor would run them one at a time.
    expect(probe.calls, 2);

    probe.gate.complete(true);
    await Future.wait([first, second]);
    expect(adapter.requests, hasLength(2));
  });
}

class _GatedProbe extends GatewayProbe {
  final Completer<bool> gate = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> isReachable() {
    calls++;
    return gate.future;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  Uri? lastUri;
  Map<String, dynamic>? lastHeaders;
  final List<Uri> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    requests.add(options.uri);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}
