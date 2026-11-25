/** Immutable runtime options for the SDK. */

export const DEFAULT_GATEWAY_HOST = '127.0.0.1';
export const DEFAULT_GATEWAY_PORT = 6625;
export const DEFAULT_PROBE_TIMEOUT_MS = 150;

export interface DeviceMetadata {
  deviceId?: string;
  deviceName?: string;
  os?: string;
  appVersion?: string;
}

export interface MocklaneConfig {
  /** Gateway host. Default `127.0.0.1`. */
  host: string;
  /** Gateway port. Default `6625`. */
  port: number;
  /**
   * When true (default), unreachable gateway → original URL.
   * When false, interceptor throws if the gateway cannot be reached.
   */
  failOpen: boolean;
  /** Fast probe timeout before deciding fail-open. */
  probeTimeoutMs: number;
  /** Device labels for the Traffic UI. Missing fields are filled from the platform. */
  device?: DeviceMetadata;
  /**
   * When false, `install()` is a no-op (use for release builds).
   * Required: there is no default.
   */
  enabled: boolean;
}

export type MocklaneInstallOptions = Partial<Omit<MocklaneConfig, 'enabled'>> &
  Pick<MocklaneConfig, 'enabled'>;

/** Minimal `globalThis` surface used for platform detection (no DOM lib needed). */
interface RuntimeScope {
  window?: { document?: unknown };
  localStorage?: {
    getItem(key: string): string | null;
    setItem(key: string, value: string): void;
  };
  crypto?: { randomUUID?: () => string };
}

const DEVICE_ID_STORAGE_KEY = 'mocklane.deviceId';

function runtimeScope(): RuntimeScope {
  return globalThis as unknown as RuntimeScope;
}

function randomToken(): string {
  const uuid = runtimeScope().crypto?.randomUUID?.();
  if (uuid) return uuid.replace(/-/g, '').slice(0, 8);
  return Math.random().toString(16).slice(2, 10).padEnd(8, '0');
}

/** Best-effort device labels for the current runtime. */
function platformDefaultDevice(): DeviceMetadata {
  const scope = runtimeScope();
  const isBrowser = scope.window?.document !== undefined;
  const os = isBrowser ? 'web' : 'node';
  return {
    deviceId: deviceIdFor(os, scope),
    deviceName: isBrowser ? 'Browser' : 'Node',
    os,
  };
}

function deviceIdFor(os: 'web' | 'node', scope: RuntimeScope): string {
  if (os === 'web') {
    try {
      const stored = scope.localStorage?.getItem(DEVICE_ID_STORAGE_KEY);
      if (stored) return stored;
      const fresh = `${os}:${randomToken()}`;
      scope.localStorage?.setItem(DEVICE_ID_STORAGE_KEY, fresh);
      return fresh;
    } catch {
      // Storage can be blocked (private mode, third-party context) — fall back
      // to a per-call id instead of failing start-up.
    }
  }
  return `${os}:${randomToken()}`;
}

/** Fill missing device fields from the platform; caller-provided values win. */
function withPlatformDefaults(device?: DeviceMetadata): DeviceMetadata {
  const base = platformDefaultDevice();
  return {
    deviceId: device?.deviceId ?? base.deviceId,
    deviceName: device?.deviceName ?? base.deviceName,
    os: device?.os ?? base.os,
    appVersion: device?.appVersion ?? base.appVersion,
  };
}

/** Mirror Kotlin/Swift validation so a bad config fails at `install()`. */
function validate(host: string, port: number, probeTimeoutMs: number): void {
  if (host.trim() === '') {
    throw new Error('host must not be blank');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`port must be in 1..65535, was ${port}`);
  }
  if (!Number.isFinite(probeTimeoutMs) || probeTimeoutMs <= 0) {
    throw new Error('probeTimeoutMs must be greater than 0');
  }
}

export function resolveConfig(options: MocklaneInstallOptions): MocklaneConfig {
  if (typeof options?.enabled !== 'boolean') {
    throw new Error('enabled is required: pass your build flag');
  }
  const host = options.host ?? DEFAULT_GATEWAY_HOST;
  const port = options.port ?? DEFAULT_GATEWAY_PORT;
  const probeTimeoutMs = options.probeTimeoutMs ?? DEFAULT_PROBE_TIMEOUT_MS;
  validate(host, port, probeTimeoutMs);
  return {
    host,
    port,
    failOpen: options.failOpen ?? true,
    probeTimeoutMs,
    device: withPlatformDefaults(options.device),
    enabled: options.enabled,
  };
}
