import { afterEach, describe, expect, it } from 'vitest';
import { Mocklane } from './mocklane.js';

describe('Mocklane façade', () => {
  afterEach(() => {
    Mocklane.uninstall();
  });

  it('install/uninstall toggles isActive', () => {
    expect(Mocklane.isActive()).toBe(false);
    Mocklane.install({ enabled: true });
    expect(Mocklane.isActive()).toBe(true);
    Mocklane.uninstall();
    expect(Mocklane.isActive()).toBe(false);
  });

  it('requires enabled', () => {
    // @ts-expect-error enabled is required
    expect(() => Mocklane.install({})).toThrow(/enabled is required/);
    expect(Mocklane.isActive()).toBe(false);
  });

  it('enabled:false leaves interceptor inactive', () => {
    Mocklane.install({ enabled: false });
    expect(Mocklane.isActive()).toBe(false);
  });

  // A disabled adapter must not clear an installation a release build may
  // still be sharing (the Kotlin adapter documents the same contract).
  it('enabled:false does not tear down an active install', () => {
    Mocklane.install({ enabled: true });
    expect(Mocklane.isActive()).toBe(true);

    Mocklane.install({ enabled: false });
    expect(Mocklane.isActive()).toBe(true);
  });

  it('an invalid config throws before touching an active install', () => {
    Mocklane.install({ enabled: true });
    expect(() => Mocklane.install({ host: '   ', enabled: true })).toThrow(
      /host must not be blank/,
    );
    expect(Mocklane.isActive()).toBe(true);
  });

  it('log is a no-op when not installed', () => {
    expect(() => Mocklane.log('x')).not.toThrow();
  });
});
