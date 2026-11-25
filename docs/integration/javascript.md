# JavaScript / TypeScript

Package: [`mocklane-sdk`](../../packages/js/README.md)

## Install

```bash
npm i -D mocklane-sdk   # or: pnpm add -D mocklane-sdk
```

## Minimal integration

```ts
import { Mocklane } from 'mocklane-sdk';

if (import.meta.env.DEV) {
  Mocklane.start();
}
```

Send requests with the normal `fetch`:

```ts
const res = await fetch('https://api.example.com/v1/me');
```

The SDK installs a global `fetch` wrapper. It intercepts `fetch` only; clients
built on axios or XHR are not covered.

## Verify

Open Mocklane Desktop and run the app. The request appears as
`GET /https://api.example.com/v1/me` in Traffic, and `Mocklane.log('…')`
appears as `SDK_LOG`.

## Advanced options

### Custom gateway

The default is `127.0.0.1:6625`. Override the port (and optionally the host):

```ts
Mocklane.start({ port: 7000 });
Mocklane.start({ host: '192.168.1.10', port: 7000 });
```

### Other options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | `true` | `false` makes `start()` a no-op |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → throw |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Labels in Desktop Traffic |

Full reference: [`packages/js/README.md`](../../packages/js/README.md).
