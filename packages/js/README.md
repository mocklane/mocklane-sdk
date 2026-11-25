# mocklane-sdk

Debug-only HTTP interceptor for JavaScript / TypeScript apps.

Routes app requests through Mocklane Desktop:

`https://api.example.com/v1/x` → `http://127.0.0.1:6625/https://api.example.com/v1/x`

If Desktop is down, **fail-open** to the original URL.

## Install

```bash
npm i -D mocklane-sdk   # or: pnpm add -D mocklane-sdk
```

ESM-only, Node 18+ (global `fetch`).

```ts
import { Mocklane } from 'mocklane-sdk';

Mocklane.start();
```

Device labels for Desktop Traffic default from the runtime: `os` is `web` in
browsers (the device id persists in `localStorage` under `mocklane.deviceId`)
and `node` elsewhere. Override any field:

```ts
Mocklane.start({ device: { deviceName: 'my-app', appVersion: '1.2.3' } });
```

Config is validated at `start()`: a blank host, a port outside 1–65535, or a
non-positive probe timeout throws.

Modules (SOLID):

| Module | Responsibility |
|--------|----------------|
| `config` | Options + defaults |
| `rewrite` | Origin-prefixed gateway URL |
| `transport` | Reachability probe |
| `interceptor` | `fetch` hook |
| `masking` | Redact secrets for logs |
| `logger` | `Mocklane.log` → `POST /__mocklane/v1/log` |
| `mocklane` | Composition root |

## License

MIT — see [LICENSE](LICENSE).
