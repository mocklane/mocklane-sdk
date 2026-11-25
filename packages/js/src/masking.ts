/**
 * Redacts secrets in log messages before they are sent.
 * Does not alter live request bodies sent through the gateway.
 */

const DEFAULT_HEADER_KEYS = [
  'authorization',
  'cookie',
  'x-api-key',
  'proxy-authorization',
  'x-auth-token',
  'set-cookie',
  'session',
];
const DEFAULT_JSON_KEYS = [
  'password',
  'token',
  'access_token',
  'refresh_token',
  'secret',
  'api_key',
  'session',
  'session_id',
  'id_token',
  'client_secret',
];

export interface MaskOptions {
  headerKeys?: string[];
  jsonKeys?: string[];
  replacement?: string;
}

export function maskHeaders(
  headers: Record<string, string>,
  options: MaskOptions = {},
): Record<string, string> {
  const keys = new Set(
    (options.headerKeys ?? DEFAULT_HEADER_KEYS).map((k) => k.toLowerCase()),
  );
  const replacement = options.replacement ?? '[REDACTED]';
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(headers)) {
    out[k] = keys.has(k.toLowerCase()) ? replacement : v;
  }
  return out;
}

export function maskJsonValue(value: unknown, options: MaskOptions = {}): unknown {
  const keys = new Set(
    (options.jsonKeys ?? DEFAULT_JSON_KEYS).map((k) => k.toLowerCase()),
  );
  const replacement = options.replacement ?? '[REDACTED]';
  return walk(value, keys, replacement);
}

function walk(value: unknown, keys: Set<string>, replacement: string): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => walk(item, keys, replacement));
  }
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = keys.has(k.toLowerCase()) ? replacement : walk(v, keys, replacement);
    }
    return out;
  }
  return value;
}

export function maskJsonString(raw: string, options: MaskOptions = {}): string {
  try {
    const parsed = JSON.parse(raw) as unknown;
    return JSON.stringify(maskJsonValue(parsed, options));
  } catch {
    return raw;
  }
}
