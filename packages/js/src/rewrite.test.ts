import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { isGatewayUrl, rewriteToGateway } from './rewrite.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const casesPath = join(__dirname, '../../../fixtures/url-rewrite.json');

interface RewriteCase {
  id: string;
  input: string;
  gatewayHost: string;
  port: number;
  expected: string;
}

const cases = JSON.parse(readFileSync(casesPath, 'utf8')) as RewriteCase[];

describe('rewriteToGateway', () => {
  for (const c of cases) {
    it(`${c.id}: ${c.input}`, () => {
      expect(
        rewriteToGateway(c.input, { host: c.gatewayHost, port: c.port }),
      ).toBe(c.expected);
    });
  }

  it('leaves relative URLs unchanged', () => {
    expect(rewriteToGateway('/v1/me')).toBe('/v1/me');
  });

  it('does not double-prefix an existing gateway URL', () => {
    const already = 'http://127.0.0.1:6625/https://api.example.com/v1';
    expect(rewriteToGateway(already)).toBe(already);
  });

  it('isGatewayUrl detects localhost gateway', () => {
    expect(isGatewayUrl('http://127.0.0.1:6625/https://x/')).toBe(true);
    expect(isGatewayUrl('https://api.example.com/v1')).toBe(false);
  });

  // `URL.port` is '' for a scheme's default port, so a gateway on :80 looked
  // like an origin URL and every request was double-prefixed.
  it('recognises a gateway on the scheme default port', () => {
    const options = { host: '127.0.0.1', port: 80 };
    expect(isGatewayUrl('http://127.0.0.1/x', options)).toBe(true);
    expect(rewriteToGateway('http://127.0.0.1/x', options)).toBe(
      'http://127.0.0.1/x',
    );
  });

  it('matches IPv6 gateway hosts with or without brackets', () => {
    expect(isGatewayUrl('http://[::1]:6625/x', { host: '::1' })).toBe(true);
    expect(isGatewayUrl('http://[::1]:6625/x', { host: '[::1]' })).toBe(true);
    expect(isGatewayUrl('http://[::1]:6625/x')).toBe(false);
  });

  it('drops credentials instead of sending them to the gateway', () => {
    expect(
      rewriteToGateway('https://user:pass@api.example.com/x'),
    ).toBe('http://127.0.0.1:6625/https://api.example.com/x');
  });
});
