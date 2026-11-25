#!/usr/bin/env node
/**
 * E2E: web-demo UI → Mocklane gateway → assert via `mocklane` CLI.
 *
 * Prerequisites:
 * - Mocklane Desktop (or `mocklane serve`) listening on :6625 + control :16625
 * - web-demo on DEMO_URL (default http://localhost:5173)
 * - `mocklane` on PATH, or MOCKLANE_BIN pointing at the binary
 *
 * Usage:
 *   node scripts/tests/e2e-web-demo.mjs
 *   DEMO_URL=http://localhost:5173 MOCKLANE_BIN=/path/to/mocklane node scripts/tests/e2e-web-demo.mjs
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { chromium } from 'playwright';

const __dirname = dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(
  readFileSync(join(__dirname, '../../samples/scenarios.json'), 'utf8'),
);

const DEMO_URL = process.env.DEMO_URL ?? 'http://127.0.0.1:5173';
const MOCKLANE = process.env.MOCKLANE_BIN ?? 'mocklane';
const SETTLE_MS = Number(process.env.SETTLE_MS ?? 2000);
const RUN_ALL_TIMEOUT_MS = Number(process.env.RUN_ALL_TIMEOUT_MS ?? 120_000);

function cli(args, { okStatuses = [0] } = {}) {
  const r = spawnSync(MOCKLANE, args, { encoding: 'utf8' });
  if (!okStatuses.includes(r.status ?? 1)) {
    throw new Error(
      `mocklane ${args.join(' ')} failed (${r.status}):\n${r.stderr || r.stdout}`,
    );
  }
  return r.stdout;
}

function trafficList() {
  const raw = cli(['traffic', 'list', '--json', '--limit', '100']);
  return JSON.parse(raw).exchanges ?? [];
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function find(exchanges, pred) {
  return exchanges.find(pred);
}

function countMatching(exchanges, pred) {
  return exchanges.filter(pred).length;
}

async function main() {
  console.log('== Mocklane SDK web-demo E2E ==');
  console.log(`demo: ${DEMO_URL}`);
  console.log(`cli:  ${MOCKLANE}`);

  const status = JSON.parse(cli(['status', '--json']));
  assert(status.listening === true, `gateway not listening: ${JSON.stringify(status)}`);
  assert(status.port === 6625, `expected port 6625, got ${status.port}`);
  console.log('✓ mocklane status listening');

  cli(['traffic', 'clear', '--json']);
  console.log('✓ traffic cleared');

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto(DEMO_URL, { waitUntil: 'networkidle' });
  await page.waitForSelector('#runAllBtn');

  await page.click('#runAllBtn');
  await page.waitForFunction(
    () => document.getElementById('out')?.textContent?.includes('Run all complete'),
    null,
    { timeout: RUN_ALL_TIMEOUT_MS },
  );
  const runAllOut = await page.textContent('#out');
  assert(runAllOut?.includes('Run all complete'), `run all did not finish:\n${runAllOut}`);
  console.log('✓ UI run all completed');

  await new Promise((r) => setTimeout(r, SETTLE_MS));
  await browser.close();

  const exchanges = trafficList();
  console.log(
    'traffic after run all:',
    exchanges.map((e) => `${e.mode} ${e.method} ${e.api_path} status=${e.status}`).join('\n  '),
  );

  const apiScenarios = catalog.scenarios.filter((s) => s.kind === 'api');
  const logScenarios = catalog.scenarios.filter((s) => s.kind === 'sdk_log');
  for (const scenario of apiScenarios) {
    const suffix = scenario.expectedTraffic.apiPathSuffix;
    const match = find(
      exchanges,
      (e) =>
        e.mode === 'FORWARD' &&
        e.method === scenario.expectedTraffic.method &&
        (e.api_path === suffix || e.api_path?.endsWith(suffix)),
    );
    assert(match, `missing FORWARD ${scenario.id} (${scenario.method} …${suffix})`);
    if (scenario.expectedTraffic.status != null) {
      assert(
        match.status === scenario.expectedTraffic.status,
        `${scenario.id} expected status ${scenario.expectedTraffic.status}, got ${match.status}`,
      );
    } else {
      assert(match.status != null, `${scenario.id} missing status`);
    }
    console.log(`✓ traffic: ${scenario.id} FORWARD ${scenario.method} …${suffix}`);
  }

  const sdkLogCount = countMatching(
    exchanges,
    (e) =>
      e.mode === 'SDK_LOG' &&
      e.method === 'POST' &&
      e.api_path === '/__mocklane/v1/log',
  );
  assert(
    sdkLogCount >= logScenarios.length,
    `expected ${logScenarios.length} SDK_LOG rows, got ${sdkLogCount}`,
  );
  console.log(`✓ traffic: ${sdkLogCount} SDK_LOG rows`);

  const forward = find(
    exchanges,
    (e) =>
      e.mode === 'FORWARD' &&
      e.method === 'GET' &&
      e.target_origin === 'https://postman-echo.com' &&
      e.api_path?.includes('/get'),
  );
  assert(
    forward?.source_label === 'web-demo',
    `source_label expected web-demo, got ${forward?.source_label}`,
  );
  console.log('✓ source_label web-demo');

  const probeErrors = exchanges.filter(
    (e) => e.mode === 'ERROR' && e.api_path === '/' && e.error_code === 'ORIGIN_MISSING',
  );
  if (probeErrors.length > 0) {
    console.warn(
      `⚠ ${probeErrors.length} probe ERROR(s) on GET / — restart Desktop on main with health endpoint`,
    );
  } else {
    console.log('✓ no ORIGIN_MISSING probe noise');
  }

  console.log('\nPASS: web-demo run-all → Desktop traffic verified via mocklane CLI');
}

main().catch((err) => {
  console.error('\nFAIL:', err.message || err);
  process.exit(1);
});
