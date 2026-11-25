# Testing

## Unit tests

Run from the repository root.

```bash
pnpm install

# JavaScript / TypeScript
pnpm --filter mocklane-sdk test
pnpm --filter mocklane-sdk build

# Dart (Dart 3.3+)
cd packages/dart
dart pub get
dart analyze --fatal-warnings
dart test

# Kotlin (JDK 17)
cd packages/kotlin
./gradlew test

# Swift (macOS)
swift test        # from the repo root, using the root SPM manifest
```

The rewrite tests in JS, Dart, and Kotlin run the shared cases in
[`fixtures/url-rewrite.json`](../fixtures/url-rewrite.json). Swift uses an
identical copy under `packages/swift/Tests/MocklaneTests/Resources/` because SPM
cannot reference files outside the package.

## CI

| System | Jobs |
|--------|------|
| GitHub Actions (`.github/workflows/ci.yml`) | `js`, `dart`, `kotlin`, `swift`, `samples-generated` |

`samples-generated` runs `pnpm generate:samples` and fails if the generated
files differ from what is committed. Edit `samples/scenarios.json`, then
regenerate.

## End-to-end: web demo ↔ Desktop

Automates the web sample's **Run all** and verifies the captures with
`mocklane traffic`.

### Goal

1. Browser loads `samples/web`.
2. **Run all** executes `S01`–`S12` and `L01`–`L02` from
   [`samples/scenarios.json`](../samples/scenarios.json).
3. `mocklane traffic list --json` shows:
   - twelve `FORWARD` rows (GET/POST/PUT/PATCH/DELETE, JSON, form, headers,
     binary, delay, 404);
   - two `SDK_LOG` rows on `POST /__mocklane/v1/log`;
   - `source_label=web-demo` on forwarded traffic.
4. No `ERROR` / `ORIGIN_MISSING` on `GET /`; the health probe must be live.

**Timeout:** `S11` uses `/delay/2`; allow up to **120s** for the run.

### Prerequisites

| Piece | How |
|-------|-----|
| Gateway + control plane | Mocklane Desktop (**Listening :6625**) or `mocklane serve` |
| Ports | Gateway `6625`, control `16625` |
| Internet | `postman-echo.com`, `jsonplaceholder.typicode.com` reachable |
| CLI | the `mocklane` binary, or `MOCKLANE_BIN=/path/to/mocklane` |
| SDK build | `pnpm --filter mocklane-sdk build` |
| Web demo | `pnpm --filter mocklane-web-demo dev` → `http://127.0.0.1:5173` |
| Playwright | `pnpm install` + `pnpm exec playwright install chromium` (once) |

```bash
mocklane status --json
# → listening true, port 6625
```

### Automated run

```bash
# Terminal A — Mocklane Desktop, or:
mocklane serve

# Terminal B — web demo
pnpm --filter mocklane-sdk build
pnpm --filter mocklane-web-demo dev

# Terminal C — E2E
MOCKLANE_BIN=/path/to/mocklane pnpm e2e:web-demo
```

Exit code `0` = pass. Exit code `1` = fail with the reason.

### Pass / fail matrix

| Check | Pass | Fail → look at |
|-------|------|----------------|
| `status.listening` | true | Start Desktop / `mocklane serve` |
| FORWARD S01–S12 | each method + path suffix present | Internet; fail-open; sample UI |
| SDK_LOG L01–L02 | ≥2 SDK_LOG rows | Desktop without log ingest |
| `source_label` | `web-demo` on forward | Device metadata in the sample bootstrap |
| No probe ERROR on `/` | zero `ORIGIN_MISSING` on `/` | Restart Desktop; health path |

### Manual fallback (no Playwright)

1. `mocklane traffic clear`
2. Open `http://127.0.0.1:5173`
3. Click **Run all**
4. Wait for `=== Run all complete ===` in the output panel
5. Inspect Traffic for all scenario rows

### When to re-run

- After editing `samples/scenarios.json` (run `pnpm generate:samples` first)
- After interceptor, rewrite, or probe changes
- After gateway reserved-path changes (`__mocklane/*`)
- Before merging SDK or sample changes
