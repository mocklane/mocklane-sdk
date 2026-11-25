/**
 * URL rewrite: absolute app URL → Mocklane gateway URL.
 *
 * Contract matches Desktop `url_map` path form:
 *   https://api.example.com/v1/x
 *   → http://127.0.0.1:6625/https://api.example.com/v1/x
 */

export interface RewriteOptions {
  host?: string;
  port?: number;
}

const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_PORT = 6625;

/**
 * Build the gateway URL for an absolute http(s) request URL.
 * Relative URLs are returned unchanged (cannot embed an origin).
 * Fragment is stripped (gateway U17). Credentials in the URL (userinfo) are
 * dropped: the gateway rejects an embedded origin that carries them (U08).
 */
export function rewriteToGateway(
  input: string | URL,
  options: RewriteOptions = {},
): string {
  const host = options.host ?? DEFAULT_HOST;
  const port = options.port ?? DEFAULT_PORT;

  let url: URL;
  try {
    url = typeof input === 'string' ? new URL(input) : new URL(input.href);
  } catch {
    return typeof input === 'string' ? input : input.href;
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return url.href;
  }

  // Already pointed at this gateway — do not double-prefix.
  if (isGatewayUrl(url, options)) {
    return url.href;
  }

  const path = url.pathname || '/';
  const search = url.search; // includes leading '?'
  const embedded = `${url.protocol}//${url.host}${path}${search}`;
  return `http://${host}:${port}/${embedded}`;
}

/**
 * True when the URL already targets the configured gateway.
 *
 * Compares the effective port: WHATWG `URL.port` is `''` for a scheme's
 * default port, so a gateway configured on `:80`/`:443` would otherwise not
 * recognise its own URLs and every request would be double-prefixed.
 */
export function isGatewayUrl(
  input: string | URL,
  options: RewriteOptions = {},
): boolean {
  const host = options.host ?? DEFAULT_HOST;
  const port = options.port ?? DEFAULT_PORT;
  try {
    const url = typeof input === 'string' ? new URL(input) : new URL(input.href);
    return sameHost(url.hostname, host) && effectivePort(url) === port;
  } catch {
    return false;
  }
}

function effectivePort(url: URL): number {
  if (url.port !== '') return Number(url.port);
  return url.protocol === 'https:' ? 443 : 80;
}

/** WHATWG keeps IPv6 brackets in `hostname`; config may spell it either way. */
function sameHost(hostname: string, host: string): boolean {
  return normalizeHost(hostname) === normalizeHost(host);
}

function normalizeHost(host: string): string {
  return host.trim().toLowerCase().replace(/^\[(.*)\]$/, '$1');
}
