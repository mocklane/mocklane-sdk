/**
 * Composition root (DIP): wires config → probe → interceptor → logger.
 * Single public façade for host apps.
 */

import { resolveConfig, type MocklaneStartOptions } from './config.js';
import { installFetchInterceptor } from './interceptor.js';
import { HttpLoggerTransport, Logger, type LogLevel } from './logger.js';
import { HttpGatewayProbe } from './transport.js';

let uninstall: (() => void) | undefined;
let logger: Logger | undefined;

export const Mocklane = {
  /**
   * Enable HTTP interception toward Mocklane Desktop.
   * Idempotent: calling again replaces the previous installation.
   */
  start(options: MocklaneStartOptions = {}): void {
    const config = resolveConfig(options);
    if (!config.enabled) {
      this.stop();
      return;
    }

    this.stop();

    const probe = new HttpGatewayProbe({
      host: config.host,
      port: config.port,
      timeoutMs: config.probeTimeoutMs,
    });

    uninstall = installFetchInterceptor({ config, probe });
    logger = new Logger(
      new HttpLoggerTransport({
        host: config.host,
        port: config.port,
        device: config.device,
      }),
    );
  },

  /** Remove the fetch hook. Safe to call when not started. */
  stop(): void {
    uninstall?.();
    uninstall = undefined;
    logger = undefined;
  },

  /** Structured log → Desktop `POST /__mocklane/v1/log`. Never throws. */
  log(message: string, level: LogLevel = 'info', tag?: string): void {
    logger?.log(message, level, tag);
  },

  /** Whether the interceptor is currently installed. */
  isActive(): boolean {
    return uninstall !== undefined;
  },
};
