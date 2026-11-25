import 'package:dio/dio.dart';
import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Mocklane.stop);

  test('rewrites when gateway reachable', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    Mocklane.start(
      dio: dio,
      probe: AlwaysReachableProbe(),
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
    Mocklane.start(dio: dio, probe: NeverReachableProbe());

    try {
      await dio.get('https://api.example.com/v1/me');
    } catch (_) {}

    expect(adapter.lastUri.toString(), 'https://api.example.com/v1/me');
  });

  test('enabled:false is a no-op', () {
    Mocklane.start(enabled: false);
    expect(Mocklane.isActive, isFalse);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  Uri? lastUri;
  Map<String, dynamic>? lastHeaders;

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
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}
