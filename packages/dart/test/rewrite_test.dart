import 'dart:convert';
import 'dart:io';

import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

void main() {
  final cases = jsonDecode(
    File('../../fixtures/url-rewrite.json').readAsStringSync(),
  ) as List<dynamic>;

  group('rewriteToGateway', () {
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      test('${c['id']}: ${c['input']}', () {
        expect(
          rewriteToGateway(
            c['input'] as String,
            host: c['gatewayHost'] as String,
            port: c['port'] as int,
          ),
          c['expected'],
        );
      });
    }

    test('leaves relative URLs unchanged', () {
      expect(rewriteToGateway('/v1/me'), '/v1/me');
    });

    test('does not double-prefix gateway URLs', () {
      const already = 'http://127.0.0.1:6625/https://api.example.com/v1';
      expect(rewriteToGateway(already), already);
    });

    test('keeps IPv6 brackets in the embedded origin', () {
      expect(
        rewriteToGateway('http://[::1]:8080/v1/me'),
        'http://127.0.0.1:6625/http://[::1]:8080/v1/me',
      );
    });

    test('drops userinfo from the embedded origin', () {
      expect(
        rewriteToGateway('https://user:pass@api.example.com/v1'),
        'http://127.0.0.1:6625/https://api.example.com/v1',
      );
    });

    test('treats a gateway URL on the scheme default port as a gateway URL',
        () {
      const already = 'http://127.0.0.1:80/https://api.example.com/v1';
      expect(isGatewayUrl(already, port: 80), isTrue);
      expect(rewriteToGateway(already, port: 80), already);
    });
  });
}
