/**
 * Transport (SRP + ISP): reachability of the Desktop gateway.
 * Implementations are injectable (DIP) so tests can stub without sockets.
 */

export interface GatewayProbe {
  /** Resolves true if the gateway appears reachable within the timeout. */
  isReachable(): Promise<boolean>;
}

export interface HttpProbeOptions {
  host: string;
  port: number;
  timeoutMs: number;
  /** Injected fetch for tests. Defaults to globalThis.fetch. */
  fetchImpl?: typeof fetch;
}

/**
 * Cheap probe via reserved health path (no Traffic row on Desktop).
 * Any network response (including 4xx) means the process is up.
 * Abort / TypeError → unreachable.
 */
export class HttpGatewayProbe implements GatewayProbe {
  private readonly url: string;
  private readonly timeoutMs: number;
  private readonly fetchImpl: typeof fetch;

  constructor(options: HttpProbeOptions) {
    this.url = `http://${options.host}:${options.port}/__mocklane/v1/health`;
    this.timeoutMs = options.timeoutMs;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  async isReachable(): Promise<boolean> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      await this.fetchImpl(this.url, {
        method: 'GET',
        signal: controller.signal,
      });
      return true;
    } catch {
      return false;
    } finally {
      clearTimeout(timer);
    }
  }
}

/** Always-reachable stub for unit tests. */
export class AlwaysReachableProbe implements GatewayProbe {
  async isReachable(): Promise<boolean> {
    return true;
  }
}

/** Always-down stub for fail-open tests. */
export class NeverReachableProbe implements GatewayProbe {
  async isReachable(): Promise<boolean> {
    return false;
  }
}
