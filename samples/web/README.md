# Web sample — `mocklane-sdk`

Reference integration: [`src/bootstrap.js`](src/bootstrap.js) (init) + [`src/scenarios.js`](src/scenarios.js) (shared catalog).

1. Start the Mocklane app (**Listening :6625**).
2. From repo root:

```bash
pnpm install
pnpm --filter mocklane-sdk build
pnpm --filter mocklane-web-demo dev
```

3. Open http://127.0.0.1:5173 → **Run all** (or run individual scenarios).
4. Confirm `S01`–`S12` FORWARD + `L01`/`L02` SDK_LOG in Traffic.

See [`../README.md`](../README.md) and [`../../docs/testing.md`](../../docs/testing.md).
