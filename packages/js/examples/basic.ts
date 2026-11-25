/**
 * Minimal usage example — run against a live Mocklane Desktop on :6625.
 *
 *   pnpm --filter mocklane-sdk build
 *   node --experimental-strip-types examples/basic.ts
 *
 * Or import from dist after build.
 */

import { Mocklane } from '../src/index.js';

Mocklane.start({
  device: {
    deviceId: 'example-device',
    deviceName: 'SDK example',
    os: 'node',
    appVersion: '0.1.0',
  },
});

Mocklane.log('example started', 'info', 'example');

const res = await fetch('https://httpbin.org/get');
console.log('status', res.status);
console.log(
  'note: with Desktop up, this request hits http://127.0.0.1:6625/https://httpbin.org/get',
);

Mocklane.stop();
