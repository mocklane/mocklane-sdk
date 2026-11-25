/**
 * Public facade: wires config → probe → fetch interceptor → logger.
 */

import { resolveConfig, type MocklaneInstallOptions } from './config.js';
import { installFetchInterceptor } from './interceptor.js';
import { HttpLoggerTransport, Logger, type LogLevel } from './logger.js';
import { HttpGatewayProbe } from './transport.js';

let removeHook: (() => void) | undefined;
let logger: Logger | undefined;

export const Mocklane = {
  /**
   * Enable HTTP interception toward Mocklane Desktop.
   * Idempotent: calling again replaces the previous installation.
   *
   * `enabled` is required and has no default: pass your build flag. A disabled
   * call is a no-op: it does not tear down an installation that is active.
   */
  install(options: MocklaneInstallOptions): void {
    const config = resolveConfig(options);
    if (!config.enabled) {
      return;
    }

    this.uninstall();

    const probe = new HttpGatewayProbe({
      host: config.host,
      port: config.port,
      timeoutMs: config.probeTimeoutMs,
    });

    removeHook = installFetchInterceptor({ config, probe });
    logger = new Logger(
      new HttpLoggerTransport({
        host: config.host,
        port: config.port,
        device: config.device,
      }),
    );
  },

  /** Remove the fetch hook. Safe to call when not installed. */
  uninstall(): void {
    removeHook?.();
    removeHook = undefined;
    logger = undefined;
  },

  /** Structured log → Desktop `POST /__mocklane/v1/log`. Never throws. */
  log(message: string, level: LogLevel = 'info', tag?: string): void {
    logger?.log(message, level, tag);
  },

  /** Whether the interceptor is currently installed. */
  isActive(): boolean {
    return removeHook !== undefined;
  },
};
