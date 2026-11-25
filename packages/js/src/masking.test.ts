import { describe, expect, it, vi } from 'vitest';
import { Logger, type LoggerTransport } from './logger.js';
import { maskHeaders, maskJsonString, maskJsonValue } from './masking.js';

describe('masking', () => {
  it('redacts sensitive headers case-insensitively', () => {
    expect(
      maskHeaders({
        Authorization: 'Bearer secret',
        'Content-Type': 'application/json',
      }),
    ).toEqual({
      Authorization: '[REDACTED]',
      'Content-Type': 'application/json',
    });
  });

  it('redacts the expanded default key set', () => {
    expect(
      maskHeaders({
        'X-Auth-Token': 't',
        'Set-Cookie': 'sid=1',
        Session: 's',
        'X-Trace': 'keep',
      }),
    ).toEqual({
      'X-Auth-Token': '[REDACTED]',
      'Set-Cookie': '[REDACTED]',
      Session: '[REDACTED]',
      'X-Trace': 'keep',
    });
    expect(
      maskJsonValue({
        session: 's',
        session_id: 's1',
        id_token: 'i',
        client_secret: 'c',
        ok: true,
      }),
    ).toEqual({
      session: '[REDACTED]',
      session_id: '[REDACTED]',
      id_token: '[REDACTED]',
      client_secret: '[REDACTED]',
      ok: true,
    });
  });

  it('redacts nested JSON keys', () => {
    expect(
      maskJsonValue({
        user: 'a',
        password: 'p',
        nested: { token: 't', ok: true },
      }),
    ).toEqual({
      user: 'a',
      password: '[REDACTED]',
      nested: { token: '[REDACTED]', ok: true },
    });
  });

  it('maskJsonString leaves non-JSON alone', () => {
    expect(maskJsonString('not-json password=x')).toBe('not-json password=x');
  });
});

describe('Logger', () => {
  it('forwards entries and swallows transport errors', async () => {
    const send = vi.fn().mockRejectedValue(new Error('down'));
    const transport: LoggerTransport = { send };
    const logger = new Logger(transport);
    expect(() => logger.log('hello', 'info', 'tag')).not.toThrow();
    await vi.waitFor(() => expect(send).toHaveBeenCalled());
    expect(send.mock.calls[0][0]).toMatchObject({
      message: 'hello',
      level: 'info',
      tag: 'tag',
    });
  });
});
