/**
 * Structured logs → reserved gateway path.
 * Never throws into the host app.
 */

import type { DeviceMetadata } from './config.js';
import { maskJsonString } from './masking.js';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogEntry {
  message: string;
  level: LogLevel;
  tag?: string;
  ts: string;
  device?: DeviceMetadata;
}

export interface LoggerTransport {
  send(entry: LogEntry): Promise<void>;
}

export interface HttpLoggerOptions {
  host: string;
  port: number;
  device?: DeviceMetadata;
  fetchImpl?: typeof fetch;
  /** Path on gateway. Default `/__mocklane/v1/log`. */
  path?: string;
}

export class HttpLoggerTransport implements LoggerTransport {
  private readonly endpoint: string;
  private readonly device?: DeviceMetadata;
  private readonly fetchImpl: typeof fetch;

  constructor(options: HttpLoggerOptions) {
    const path = options.path ?? '/__mocklane/v1/log';
    this.endpoint = `http://${options.host}:${options.port}${path}`;
    this.device = options.device;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  async send(entry: LogEntry): Promise<void> {
    const body = JSON.stringify({
      ...entry,
      message: maskJsonString(entry.message),
      device: entry.device ?? this.device,
    });
    const headers: Record<string, string> = {
      'content-type': 'application/json',
    };
    const device = entry.device ?? this.device;
    if (device?.deviceId) headers['X-Mocklane-Device-Id'] = device.deviceId;
    if (device?.deviceName) headers['X-Mocklane-Device-Name'] = device.deviceName;
    if (device?.os) headers['X-Mocklane-Os'] = device.os;
    if (device?.appVersion) headers['X-Mocklane-App-Version'] = device.appVersion;

    await this.fetchImpl(this.endpoint, {
      method: 'POST',
      headers,
      body,
    });
  }
}

export class Logger {
  constructor(private readonly transport: LoggerTransport) {}

  log(message: string, level: LogLevel = 'info', tag?: string): void {
    const entry: LogEntry = {
      message,
      level,
      tag,
      ts: new Date().toISOString(),
    };
    void this.transport.send(entry).catch(() => {
      /* fail-open: never surface log errors */
    });
  }
}
