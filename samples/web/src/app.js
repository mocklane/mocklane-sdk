import './bootstrap.js';
import { isMocklaneEnabled } from './bootstrap.js';
import { scenarios, runScenario, runAllScenarios } from './scenarios.js';

const out = document.getElementById('out');
const list = document.getElementById('scenarioList');
const runAllBtn = document.getElementById('runAllBtn');
const clearBtn = document.getElementById('clearBtn');

let busy = false;

function say(msg) {
  out.textContent = msg;
}

function setBusy(next) {
  busy = next;
  runAllBtn.disabled = next;
  clearBtn.disabled = next;
  list.querySelectorAll('button[data-run]').forEach((btn) => {
    btn.disabled = next;
  });
}

function pathLabel(scenario) {
  if (scenario.kind === 'sdk_log') return 'POST /__mocklane/v1/log';
  try {
    const u = new URL(scenario.url);
    return `${scenario.method} ${u.pathname}${u.search}`;
  } catch {
    return scenario.method ?? scenario.kind;
  }
}

function renderList() {
  list.innerHTML = '';
  for (const scenario of scenarios) {
    const row = document.createElement('div');
    row.className = 'scenario-row';

    const meta = document.createElement('div');
    meta.className = 'scenario-meta';
    meta.innerHTML =
      `<strong>${scenario.id}</strong> ${scenario.label}` +
      `<span class="scenario-path">${pathLabel(scenario)}</span>`;

    const runBtn = document.createElement('button');
    runBtn.type = 'button';
    runBtn.textContent = 'Run';
    runBtn.dataset.run = scenario.id;
    runBtn.addEventListener('click', () => runOne(scenario.id));

    row.append(meta, runBtn);
    list.append(row);
  }
}

async function runOne(id) {
  const scenario = scenarios.find((s) => s.id === id);
  if (!scenario || busy) return;
  setBusy(true);
  say(`Running ${id} …`);
  try {
    const result = await runScenario(scenario);
    say(`[${result.id}] ${result.ok ? 'OK' : 'FAIL'}\n${result.detail ?? ''}`);
  } catch (err) {
    say(`[${id}] error: ${err}`);
  } finally {
    setBusy(false);
  }
}

runAllBtn.addEventListener('click', async () => {
  if (busy) return;
  setBusy(true);
  say('Running all scenarios …\n');
  const lines = [];
  await runAllScenarios({
    onProgress: (id, phase, result) => {
      if (phase === 'running') {
        lines.push(`… ${id}`);
        say(`${lines.join('\n')}\n`);
      } else if (result) {
        lines[lines.length - 1] = `[${id}] ${result.ok ? 'OK' : 'FAIL'} status=${result.status ?? '—'}`;
        say(`${lines.join('\n')}\n`);
      }
    },
  });
  say(`${lines.join('\n')}\n\n=== Run all complete ===`);
  setBusy(false);
});

clearBtn.addEventListener('click', () => say('Ready.'));

if (!isMocklaneEnabled()) {
  say('Production build — Mocklane.install() skipped. API calls use fail-open direct fetch.');
}

renderList();
