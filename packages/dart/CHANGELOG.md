# Changelog

## 0.1.1

- Documentation and release updates. No API changes.

## 0.1.0

- Initial release.
- `Mocklane.install()` wires a Dio interceptor that rewrites absolute URLs to the Mocklane app gateway (`:6625`), with fail-open when the Mocklane app is down.
- `Mocklane.dio` shared client and `Mocklane.interceptor` for existing clients.
- Gateway reachability probe (requests are not serialised behind it), device metadata headers, and per-client config.
- Device labels default from the platform (`Platform.operatingSystem`, hostname on desktop) when the app does not provide them.
- `MocklaneConfig` validates host, port, and probe timeout at construction.
- `Mocklane.log()` posts structured logs with JSON secret masking.
- `enabled` is required and has no default; a disabled `Mocklane.install()` is a no-op that leaves a running installation untouched, and an invalid config throws before anything is stopped.
- IPv6 literal origins keep their brackets in the embedded gateway URL; userinfo is dropped (the Mocklane app rejects embedded credentials).
- `Mocklane.uninstall()` closes the probe and log transport it created (injected probes stay caller-owned).
- Log masking replaces `password`, `token`, `access_token`, `refresh_token`, `id_token`, `secret`, `client_secret`, `api_key`, `session`, and `session_id` in JSON messages.
