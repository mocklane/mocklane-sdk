import 'package:mocklane/mocklane.dart';
import 'package:test/test.dart';

void main() {
  test('maskHeaders redacts Authorization', () {
    expect(
      maskHeaders({
        'Authorization': 'Bearer x',
        'Content-Type': 'application/json',
      }),
      {
        'Authorization': '[REDACTED]',
        'Content-Type': 'application/json',
      },
    );
  });

  test('maskJsonValue redacts nested secrets', () {
    expect(
      maskJsonValue({
        'user': 'a',
        'password': 'p',
        'nested': {'token': 't'},
      }),
      {
        'user': 'a',
        'password': '[REDACTED]',
        'nested': {'token': '[REDACTED]'},
      },
    );
  });
}
