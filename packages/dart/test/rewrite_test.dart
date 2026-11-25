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
  });
}
