import { afterEach, describe, expect, it, vi } from 'vitest';
import { resolveConfig } from './config.js';
import { installFetchInterceptor } from './interceptor.js';
import { AlwaysReachableProbe, NeverReachableProbe } from './transport.js';

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
      config: resolveConfig(),
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
      config: resolveConfig({ failOpen: true }),
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
      config: resolveConfig({ failOpen: false }),
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
      config: resolveConfig(),
      probe: new AlwaysReachableProbe(),
      fetchImpl: stub,
    });

    await fetch('/local');
    expect(seen).toEqual(['/local']);
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
      config: resolveConfig({
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
});
