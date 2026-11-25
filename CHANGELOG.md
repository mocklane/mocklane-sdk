# Changelog

## 0.1.1

- Public repository recreated with the current SDK sources and documentation.
- Documentation refreshed across the JS, Dart, Swift, and Kotlin guides.
- Release workflow hardening: pinned GitHub Actions, npm provenance, and
  validation of the Maven Central signing key.

## 0.1.0

- Initial release of the Mocklane SDK for JavaScript, Dart/Flutter, Swift, and
  Kotlin/Android/JVM.
- Debug-only interception that rewrites absolute HTTP(S) URLs to the Mocklane
  Desktop gateway (`127.0.0.1:6625`), with fail-open when Desktop is unreachable.
- Opt-in `enabled` flag, gateway health probe, device metadata headers, and
  structured logs via `Mocklane.log`.
- JSON secret masking in JS, Dart, and Swift log messages. Kotlin sends log
  messages as-is; mask secrets before logging.
