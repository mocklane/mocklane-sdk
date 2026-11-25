import { afterEach, describe, expect, it, vi } from 'vitest';
import { resolveConfig } from './config.js';
import { HttpGatewayProbe } from './transport.js';

describe('resolveConfig', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('applies defaults for port and fail-open', () => {
    const c = resolveConfig({ enabled: false });
    expect(c.port).toBe(6625);
    expect(c.host).toBe('127.0.0.1');
    expect(c.failOpen).toBe(true);
    expect(c.enabled).toBe(false);
  });

  it('merges partial overrides', () => {
    const c = resolveConfig({ port: 7000, failOpen: false, enabled: false });
    expect(c.port).toBe(7000);
    expect(c.failOpen).toBe(false);
    expect(c.enabled).toBe(false);
  });

  describe('device defaults', () => {
    it('fills missing labels from the Node runtime', () => {
      const c = resolveConfig({ enabled: false });
      expect(c.device?.deviceId).toMatch(/^node:[0-9a-f]{8}$/);
      expect(c.device?.deviceName).toBe('Node');
      expect(c.device?.os).toBe('node');
      expect(c.device?.appVersion).toBeUndefined();
    });

    it('keeps provided labels and fills the rest', () => {
      const c = resolveConfig({
        enabled: false,
        device: { deviceName: 'my-app', appVersion: '1.2.3' },
      });
      expect(c.device?.deviceName).toBe('my-app');
      expect(c.device?.appVersion).toBe('1.2.3');
      expect(c.device?.deviceId).toMatch(/^node:/);
      expect(c.device?.os).toBe('node');
    });

    it('uses browser labels and persists a stable id in localStorage', () => {
      const store = new Map<string, string>();
      vi.stubGlobal('window', { document: {} });
      vi.stubGlobal('localStorage', {
        getItem: (key: string) => store.get(key) ?? null,
        setItem: (key: string, value: string) => {
          store.set(key, value);
        },
      });

      const first = resolveConfig({ enabled: false });
      const second = resolveConfig({ enabled: false });
      expect(first.device?.os).toBe('web');
      expect(first.device?.deviceName).toBe('Browser');
      expect(first.device?.deviceId).toMatch(/^web:[0-9a-f]{8}$/);
      expect(second.device?.deviceId).toBe(first.device?.deviceId);
      expect(store.get('mocklane.deviceId')).toBe(first.device?.deviceId);
    });

    it('still starts when browser storage throws', () => {
      vi.stubGlobal('window', { document: {} });
      vi.stubGlobal('localStorage', {
        getItem: () => {
          throw new Error('blocked');
        },
        setItem: () => {
          throw new Error('blocked');
        },
      });

      const c = resolveConfig({ enabled: false });
      expect(c.device?.os).toBe('web');
      expect(c.device?.deviceId).toMatch(/^web:/);
    });
  });

  describe('validation', () => {
    it('requires enabled', () => {
      // @ts-expect-error enabled is required
      expect(() => resolveConfig({})).toThrow(/enabled is required/);
    });

    it('rejects a blank host', () => {
      expect(() => resolveConfig({ host: '   ', enabled: false })).toThrow(
        'host must not be blank',
      );
    });

    it('rejects ports outside 1..65535', () => {
      expect(() => resolveConfig({ port: 0, enabled: false })).toThrow(
        'port must be in 1..65535',
      );
      expect(() => resolveConfig({ port: 70000, enabled: false })).toThrow(
        'port must be in 1..65535',
      );
      expect(() => resolveConfig({ port: 6625.5, enabled: false })).toThrow(
        'port must be in 1..65535',
      );
    });

    it('rejects non-positive probe timeouts', () => {
      expect(() => resolveConfig({ probeTimeoutMs: 0, enabled: false })).toThrow(
        'probeTimeoutMs must be greater than 0',
      );
      expect(() => resolveConfig({ probeTimeoutMs: -1, enabled: false })).toThrow(
        'probeTimeoutMs must be greater than 0',
      );
    });
  });
});

describe('HttpGatewayProbe', () => {
  it('returns true when fetch resolves', async () => {
    const probe = new HttpGatewayProbe({
      host: '127.0.0.1',
      port: 6625,
      timeoutMs: 50,
      fetchImpl: async () => new Response(null, { status: 404 }),
    });
    expect(await probe.isReachable()).toBe(true);
  });

  it('returns false when fetch rejects', async () => {
    const probe = new HttpGatewayProbe({
      host: '127.0.0.1',
      port: 6625,
      timeoutMs: 50,
      fetchImpl: async () => {
        throw new TypeError('fetch failed');
      },
    });
    expect(await probe.isReachable()).toBe(false);
  });
});
