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

  test('maskHeaders redacts session and auth-token headers', () {
    expect(
      maskHeaders({
        'Set-Cookie': 'sid=1',
        'X-Auth-Token': 'abc',
        'Accept': '*/*',
      }),
      {
        'Set-Cookie': '[REDACTED]',
        'X-Auth-Token': '[REDACTED]',
        'Accept': '*/*',
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

  test('maskJsonValue redacts session, id_token and client_secret keys', () {
    expect(
      maskJsonValue({
        'session': 's',
        'session_id': 'sid',
        'id_token': 'idt',
        'client_secret': 'cs',
        'name': 'keep',
      }),
      {
        'session': '[REDACTED]',
        'session_id': '[REDACTED]',
        'id_token': '[REDACTED]',
        'client_secret': '[REDACTED]',
        'name': 'keep',
      },
    );
  });
}
