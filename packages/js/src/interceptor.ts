/**
 * Interceptor (SRP): hook `fetch`, rewrite to gateway when reachable.
 * Depends on GatewayProbe abstraction (DIP); fail-open policy from config.
 */

import type { DeviceMetadata, MocklaneConfig } from './config.js';
import { isGatewayUrl, rewriteToGateway } from './rewrite.js';
import type { GatewayProbe } from './transport.js';

export interface FetchInterceptorDeps {
  config: MocklaneConfig;
  probe: GatewayProbe;
  fetchImpl?: typeof fetch;
}

const DEVICE_HEADERS: Record<keyof Required<DeviceMetadata>, string> = {
  deviceId: 'X-Mocklane-Device-Id',
  deviceName: 'X-Mocklane-Device-Name',
  os: 'X-Mocklane-Os',
  appVersion: 'X-Mocklane-App-Version',
};

/**
 * Installs a global fetch wrapper. Returns uninstall().
 * Relative URLs and non-http(s) schemes are left untouched.
 */
export function installFetchInterceptor(deps: FetchInterceptorDeps): () => void {
  const original = deps.fetchImpl ?? globalThis.fetch.bind(globalThis);
  const { config, probe } = deps;

  const wrapped: typeof fetch = async (input, init) => {
    const originalUrl = requestUrl(input);
    if (!shouldRewrite(originalUrl, config)) {
      return original(input, init);
    }

    const reachable = await probe.isReachable();
    if (!reachable) {
      if (config.failOpen) {
        return original(input, init);
      }
      throw new Error(
        `Mocklane gateway unreachable at ${config.host}:${config.port}`,
      );
    }

    const gatewayUrl = rewriteToGateway(originalUrl, {
      host: config.host,
      port: config.port,
    });
    const nextInit = mergeDeviceHeaders(init, config.device);
    return original(gatewayUrl, nextInit);
  };

  globalThis.fetch = wrapped;
  return () => {
    globalThis.fetch = original;
  };
}

function requestUrl(input: RequestInfo | URL): string {
  if (typeof input === 'string') return input;
  if (input instanceof URL) return input.href;
  return input.url;
}

function shouldRewrite(url: string, config: MocklaneConfig): boolean {
  if (isGatewayUrl(url, { host: config.host, port: config.port })) {
    return false;
  }
  try {
    const u = new URL(url);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    // Relative URL — leave to the host app / browser.
    return false;
  }
}

function mergeDeviceHeaders(
  init: RequestInit | undefined,
  device: DeviceMetadata | undefined,
): RequestInit | undefined {
  if (!device) return init;
  const headers = new Headers(init?.headers);
  for (const [key, headerName] of Object.entries(DEVICE_HEADERS) as [
    keyof DeviceMetadata,
    string,
  ][]) {
    const value = device[key];
    if (value) headers.set(headerName, value);
  }
  return { ...init, headers };
}
