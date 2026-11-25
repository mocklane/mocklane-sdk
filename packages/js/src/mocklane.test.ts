import { afterEach, describe, expect, it } from 'vitest';
import { Mocklane } from './mocklane.js';

describe('Mocklane façade', () => {
  afterEach(() => {
    Mocklane.stop();
  });

  it('start/stop toggles isActive', () => {
    expect(Mocklane.isActive()).toBe(false);
    Mocklane.start({ enabled: true });
    expect(Mocklane.isActive()).toBe(true);
    Mocklane.stop();
    expect(Mocklane.isActive()).toBe(false);
  });

  it('enabled:false leaves interceptor inactive', () => {
    Mocklane.start({ enabled: false });
    expect(Mocklane.isActive()).toBe(false);
  });

  it('log is a no-op when not started', () => {
    expect(() => Mocklane.log('x')).not.toThrow();
  });
});
