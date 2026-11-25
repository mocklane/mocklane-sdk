import { describe, expect, it, vi } from 'vitest';
import type { DeviceMetadata } from './config.js';
import { HttpLoggerTransport, Logger } from './logger.js';

describe('HttpLoggerTransport', () => {
  it('posts masked structured JSON with device headers', async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetchImpl: typeof fetch = (async (input, init) => {
      calls.push({ url: String(input), init: init ?? {} });
      return { ok: true } as unknown as Response;
    }) as unknown as typeof fetch;

    const device: DeviceMetadata = { deviceId: 'js-test', deviceName: 'js-log' };
    const transport = new HttpLoggerTransport({
      host: '127.0.0.1',
      port: 6625,
      device,
      fetchImpl,
    });

    await transport.send({
      message: '{"user":"a","password":"hunter2"}',
      level: 'info',
      tag: 'home',
      ts: '2026-01-01T00:00:00Z',
    });

    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('http://127.0.0.1:6625/__mocklane/v1/log');
    const init = calls[0].init;
    expect(init.method).toBe('POST');
    const headers = init.headers as Record<string, string>;
    expect(headers['content-type']).toBe('application/json');
    expect(headers['X-Mocklane-Device-Id']).toBe('js-test');
    expect(headers['X-Mocklane-Device-Name']).toBe('js-log');
    const body = JSON.parse(String(init.body)) as Record<string, unknown>;
    expect(body.message).toBe('{"user":"a","password":"[REDACTED]"}');
    expect(body.level).toBe('info');
    expect(body.tag).toBe('home');
    expect(body.device).toEqual(device);
  });

  it('leaves non-JSON messages unchanged', async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetchImpl: typeof fetch = (async (input, init) => {
      calls.push({ url: String(input), init: init ?? {} });
      return { ok: true } as unknown as Response;
    }) as unknown as typeof fetch;
    const transport = new HttpLoggerTransport({ host: '127.0.0.1', port: 6625, fetchImpl });
    await transport.send({ message: 'plain text', level: 'warn', ts: 'x' });
    expect(calls).toHaveLength(1);
    const body = JSON.parse(String(calls[0].init.body)) as Record<string, unknown>;
    expect(body.message).toBe('plain text');
  });
});

describe('Logger', () => {
  it('never throws when the transport fails', async () => {
    const send = vi.fn().mockRejectedValue(new Error('down'));
    const logger = new Logger({ send });
    expect(() => logger.log('hello', 'info', 'tag')).not.toThrow();
    await vi.waitFor(() => expect(send).toHaveBeenCalled());
  });
});
