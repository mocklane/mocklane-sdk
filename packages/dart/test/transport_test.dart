import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocklane/src/transport.dart';
import 'package:test/test.dart';

void main() {
  group('HttpGatewayProbe', () {
    test('reports reachable on any HTTP response', () async {
      final client = MockClient((_) async => http.Response('not found', 404));
      final probe = HttpGatewayProbe(
        host: '127.0.0.1',
        port: 6625,
        timeout: const Duration(milliseconds: 150),
        client: client,
      );
      expect(await probe.isReachable(), isTrue);
    });

    test('reports unreachable when the request fails', () async {
      final client = MockClient((_) async => throw Exception('connection refused'));
      final probe = HttpGatewayProbe(
        host: '127.0.0.1',
        port: 6625,
        timeout: const Duration(milliseconds: 150),
        client: client,
      );
      expect(await probe.isReachable(), isFalse);
    });

    test('reports unreachable on timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('ok', 200);
      });
      final probe = HttpGatewayProbe(
        host: '127.0.0.1',
        port: 6625,
        timeout: const Duration(milliseconds: 50),
        client: client,
      );
      expect(await probe.isReachable(), isFalse);
    });
  });
}
