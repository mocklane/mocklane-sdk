/**
 * Mocklane integration bootstrap (debug builds).
 * See ../../../docs/integration.md.
 */
import { Mocklane } from 'mocklane-sdk';

const isDev = import.meta.env.DEV;

export function initMocklane() {
  if (!isDev) return;
  Mocklane.start({
    device: {
      deviceId: 'web-demo-1',
      deviceName: 'web-demo',
      os: 'web',
      appVersion: '0.1.0',
    },
  });
}

export function isMocklaneEnabled() {
  return isDev;
}

initMocklane();
