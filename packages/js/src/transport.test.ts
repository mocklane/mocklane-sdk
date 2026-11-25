import { afterEach, describe, expect, it, vi } from 'vitest';
import { HttpGatewayProbe } from './transport.js';

describe('HttpGatewayProbe', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('reports reachable on any HTTP response', async () => {
    const fetchImpl: typeof fetch = (async () =>
      ({ status: 404 }) as unknown as Response) as unknown as typeof fetch;
    const probe = new HttpGatewayProbe({ host: '127.0.0.1', port: 6625, timeoutMs: 150, fetchImpl });
    await expect(probe.isReachable()).resolves.toBe(true);
  });

  it('reports unreachable when fetch rejects', async () => {
    const fetchImpl: typeof fetch = (async () => {
      throw new TypeError('connection refused');
    }) as unknown as typeof fetch;
    const probe = new HttpGatewayProbe({ host: '127.0.0.1', port: 6625, timeoutMs: 150, fetchImpl });
    await expect(probe.isReachable()).resolves.toBe(false);
  });

  it('aborts and reports unreachable after the timeout', async () => {
    vi.useFakeTimers();
    const fetchImpl: typeof fetch = (async (_input, init) => {
      await new Promise<never>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new Error('aborted')));
      });
    }) as unknown as typeof fetch;
    const probe = new HttpGatewayProbe({ host: '127.0.0.1', port: 6625, timeoutMs: 150, fetchImpl });

    const pending = probe.isReachable();
    await vi.advanceTimersByTimeAsync(151);
    await expect(pending).resolves.toBe(false);
  });
});
