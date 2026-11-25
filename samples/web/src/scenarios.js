import catalog from '../../scenarios.json';
import { Mocklane } from 'mocklane-sdk';
import { isMocklaneEnabled } from './bootstrap.js';

export const scenarios = catalog.scenarios;

export function apiScenarios() {
  return scenarios.filter((s) => s.kind === 'api');
}

export function logScenarios() {
  return scenarios.filter((s) => s.kind === 'sdk_log');
}

function formatBody(scenario, data, contentType) {
  if (scenario.responseKind === 'binary') {
    if (data instanceof ArrayBuffer) {
      return `${data.byteLength} bytes (${contentType || 'binary'})`;
    }
    return `${String(data).length} bytes`;
  }
  if (typeof data === 'string') return data.slice(0, 600);
  try {
    return JSON.stringify(data, null, 2).slice(0, 600);
  } catch {
    return String(data).slice(0, 600);
  }
}

export async function runScenario(scenario) {
  if (scenario.kind === 'sdk_log') {
    if (!isMocklaneEnabled()) {
      return { id: scenario.id, ok: false, detail: 'Mocklane disabled outside dev.' };
    }
    Mocklane.log(scenario.logMessage, scenario.logLevel, scenario.logTag);
    return {
      id: scenario.id,
      ok: true,
      detail: `SDK_LOG ${scenario.logLevel} tag=${scenario.logTag}`,
    };
  }

  const headers = { ...(scenario.headers ?? {}) };
  const init = { method: scenario.method, headers };
  if (scenario.body != null) {
    headers['Content-Type'] = scenario.contentType ?? 'application/json';
    init.body = scenario.body;
  }

  const res = await fetch(scenario.url, init);
  const contentType = res.headers.get('content-type') ?? '';
  let data;
  if (scenario.responseKind === 'binary') {
    data = await res.arrayBuffer();
  } else if (contentType.includes('application/json')) {
    data = await res.json();
  } else {
    data = await res.text();
  }

  return {
    id: scenario.id,
    ok: res.ok || scenario.id === 'S12',
    status: res.status,
    detail:
      `status ${res.status}\n` +
      `Traffic: FORWARD ${scenario.method} …${scenario.expectedTraffic?.apiPathSuffix ?? ''}\n\n` +
      formatBody(scenario, data, contentType),
  };
}

export async function runAllScenarios({ onProgress, delayMs = 300 } = {}) {
  const results = [];
  for (const scenario of scenarios) {
    onProgress?.(scenario.id, 'running');
    try {
      const result = await runScenario(scenario);
      results.push(result);
      onProgress?.(scenario.id, 'done', result);
    } catch (err) {
      const result = { id: scenario.id, ok: false, detail: `error: ${err}` };
      results.push(result);
      onProgress?.(scenario.id, 'error', result);
    }
    if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs));
  }
  return results;
}
