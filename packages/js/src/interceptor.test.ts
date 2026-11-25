import { afterEach, describe, expect, it } from 'vitest';
import { resolveConfig, type MocklaneInstallOptions } from './config.js';
import { installFetchInterceptor } from './interceptor.js';
import { AlwaysReachableProbe, NeverReachableProbe } from './transport.js';

const enabled = (overrides: Partial<MocklaneInstallOptions> = {}) =>
  resolveConfig({ ...overrides, enabled: true });

describe('installFetchInterceptor', () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it('rewrites absolute https URLs when gateway is reachable', async () => {
    const seen: string[] = [];
    const stub: typeof fetch = async (input) => {
      seen.push(String(input));
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled(),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('https://api.example.com/v1/me');
    expect(seen).toEqual([
      'http://127.0.0.1:6625/https://api.example.com/v1/me',
    ]);
    uninstall();
  });

  it('fail-opens to original URL when gateway is down', async () => {
    const seen: string[] = [];
    const stub: typeof fetch = async (input) => {
      seen.push(String(input));
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled({ failOpen: true }),
      probe: new NeverReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('https://api.example.com/v1/me');
    expect(seen).toEqual(['https://api.example.com/v1/me']);
    uninstall();
  });

  it('throws when failOpen is false and gateway is down', async () => {
    const stub: typeof fetch = async () => new Response('ok');
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled({ failOpen: false }),
      probe: new NeverReachableProbe(),
      fetchImpl: stub,
    });

    await expect(fetch('https://api.example.com/v1/me')).rejects.toThrow(
      /unreachable/i,
    );
    uninstall();
  });

  it('leaves relative URLs alone', async () => {
    const seen: string[] = [];
    const stub: typeof fetch = async (input) => {
      seen.push(String(input));
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled(),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('/local');
    expect(seen).toEqual(['/local']);
    uninstall();
  });

  it('does nothing when the config is disabled', async () => {
    const seen: string[] = [];
    const stub: typeof fetch = async (input) => {
      seen.push(String(input));
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: resolveConfig({ enabled: false }),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('https://api.example.com/v1/me');
    expect(seen).toEqual(['https://api.example.com/v1/me']);
    uninstall();
  });

  it('attaches device metadata headers', async () => {
    let headers: Headers | undefined;
    const stub: typeof fetch = async (_input, init) => {
      headers = new Headers(init?.headers);
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled({
        device: { deviceId: 'dev-1', os: 'ios', appVersion: '1.0.0' },
      }),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('https://api.example.com/v1');
    expect(headers?.get('X-Mocklane-Device-Id')).toBe('dev-1');
    expect(headers?.get('X-Mocklane-Os')).toBe('ios');
    expect(headers?.get('X-Mocklane-App-Version')).toBe('1.0.0');
    uninstall();
  });

  // A `Request` carries its own method, body and headers; rewriting it with
  // `fetch(gatewayUrl, init)` used to drop all three.
  it('preserves method, body and headers from a Request input', async () => {
    let captured: { input: RequestInfo | URL; init?: RequestInit } | undefined;
    const stub: typeof fetch = async (input, init) => {
      captured = { input, init };
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled({ device: { deviceName: 'js-test' } }),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    const request = new Request('https://api.example.com/v1/items', {
      method: 'POST',
      body: '{"a":1}',
      headers: { Authorization: 'Bearer t' },
    });
    await fetch(request);

    const rewritten = captured?.input as Request;
    expect(rewritten.url).toBe(
      'http://127.0.0.1:6625/https://api.example.com/v1/items',
    );
    expect(rewritten.method).toBe('POST');
    expect(await rewritten.text()).toBe('{"a":1}');
    expect(rewritten.headers.get('Authorization')).toBe('Bearer t');
    expect(rewritten.headers.get('X-Mocklane-Device-Name')).toBe('js-test');
    expect(captured?.init).toBeUndefined();
    uninstall();
  });

  it('merges device headers into caller-supplied init headers', async () => {
    let captured: { input: RequestInfo | URL; init?: RequestInit } | undefined;
    const stub: typeof fetch = async (input, init) => {
      captured = { input, init };
      return new Response('ok');
    };
    globalThis.fetch = stub;

    const uninstall = installFetchInterceptor({
      config: enabled({ device: { deviceName: 'js-test' } }),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    const request = new Request('https://api.example.com/v1/items');
    await fetch(request, { headers: { 'X-Custom': '1' } });

    const initHeaders = new Headers(captured?.init?.headers);
    expect(initHeaders.get('X-Custom')).toBe('1');
    expect(initHeaders.get('X-Mocklane-Device-Name')).toBe('js-test');
    uninstall();
  });
});
