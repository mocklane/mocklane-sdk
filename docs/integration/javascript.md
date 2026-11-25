# JavaScript / TypeScript

Package: [`mocklane-sdk`](../../packages/js/README.md) · Overview: [`INTEGRATION.md`](../INTEGRATION.md)

The SDK wraps the global `fetch` function. While interception is enabled, it sends every absolute `http(s)` request to `http://127.0.0.1:6625/<original-url>` instead of its original URL.

Requirements: an ESM runtime with `fetch` — Node.js 18 or later, or a modern browser.

## Install

```bash
npm i -D mocklane-sdk
```

## Quick start

Enable interception before the app sends requests:

```ts
import { Mocklane } from 'mocklane-sdk';

if (import.meta.env.DEV) {
  Mocklane.install({ enabled: true });
}
```

Then call `fetch` as before:

```ts
const res = await fetch('https://api.example.com/v1/me');
```

No other change is needed. The wrapper rewrites the URL when the Mocklane app is reachable and uses the original URL when it is not. `Request` objects keep their method, body, and headers:

```ts
await fetch(
  new Request('https://api.example.com/v1/items', {
    method: 'POST',
    headers: { Authorization: 'Bearer …' },
    body: JSON.stringify({ name: 'one' }),
  }),
);
```

`install()` is idempotent: calling it again replaces the previous installation. `enabled` is required and has no default: pass your build flag, and `false` makes `install()` a no-op.

## Verify

Run the app with the Mocklane app open. The request appears as `GET /https://api.example.com/v1/me` in Traffic, and `Mocklane.log('…')` appears as an `SDK_LOG` row.

## Advanced

### Custom gateway

The default is `127.0.0.1:6625`. Override the port, or the host as well:

```ts
Mocklane.install({ enabled: true, port: 7000 });
// or:
Mocklane.install({ enabled: true, host: '192.168.1.10', port: 7000 });
```

### Options

| Option | Default | Meaning |
|--------|---------|---------|
| `enabled` | — (required) | Pass your build flag; `false` makes `install()` a no-op |
| `host` | `127.0.0.1` | Gateway host |
| `port` | `6625` | Gateway port |
| `failOpen` | `true` | Unreachable gateway → original request; `false` → throw |
| `probeTimeoutMs` | `150` | Reachability-probe timeout |
| `device` | platform default | Device labels in Traffic |

Config is validated at `install()`: a blank host, a port outside 1–65535, or a non-positive probe timeout throws. Full reference: [`packages/js/README.md`](../../packages/js/README.md).

### Lifecycle

`Mocklane.uninstall()` removes the hook and is safe to call when interception is not running. `Mocklane.isActive()` reports whether the hook is installed.

```ts
Mocklane.uninstall();      // restore the original fetch
Mocklane.isActive();  // false
```

### Local checkout

For SDK development, point the app at the package directory instead of the registry:

```bash
pnpm add mocklane-sdk@file:<path-to-sdk>/packages/js
```

### Limitations

- Only the global `fetch` is wrapped. Clients built on axios, `XMLHttpRequest`, or another transport are not covered.
- In a browser, the wrapper rewrites the URL before the browser attaches cookies, so `Cookie`/`Set-Cookie` handling sees the gateway host instead of your origin. If cookie-bound auth matters, run the app on Node/edge or use an HTTP client that exposes the original URL.

## Logging and privacy

`Mocklane.log(message, level?, tag?)` posts the message to the gateway, and the Mocklane app stores the captured traffic. Masking is best-effort and applies only to the log message. A message is scanned only when it is valid JSON, and only the keys `password`, `token`, `access_token`, `refresh_token`, `id_token`, `secret`, `client_secret`, `api_key`, `session`, and `session_id` are replaced. The tag and free text are not scanned. Request and response bodies are never redacted.

The gateway is plain HTTP without authentication. The `host` setting must stay on loopback (`127.0.0.1`); pointing it at a LAN address sends captured credentials to everyone on that network.
