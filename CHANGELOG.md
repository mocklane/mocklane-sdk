# Changelog

## 0.1.1

- Public repository recreated with the current SDK sources and documentation.
- Documentation rewritten for clarity, with refreshed integration, testing, and
  publishing guides.
- Release workflow hardening: npm Trusted Publishing support, npm provenance,
  and validation of the Maven Central signing key.

## 0.1.0

Initial release of the Mocklane SDK for JavaScript, Dart/Flutter, Swift, and Kotlin/Android/JVM.

- Debug-only interception: absolute HTTP(S) URLs are rewritten to the Mocklane app gateway (`127.0.0.1:6625`), with fail-open when the Mocklane app is unreachable.
- Required `enabled` flag (no default in any SDK), gateway health probe, device metadata headers, and structured logs via `Mocklane.log`.
- One adapter per HTTP client: `fetch` wrapper (JavaScript), Dio interceptor (Dart), `URLProtocol` (Swift), OkHttp interceptors and a Ktor plugin (Kotlin).
- Log masking for JavaScript, Dart, and Swift: JSON-shaped messages have a fixed set of secret keys replaced. Kotlin sends messages as-is.
- OkHttp keeps cookies keyed to the original origin. Ktor and Swift document their cookie limitations.
- Same-origin redirects stay captured, including relative `Location` headers, which the Mocklane app rewrites through the gateway (issue #114).
- The Kotlin adapters do not use `java.time` and need no core-library desugaring.
