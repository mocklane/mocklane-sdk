# Changelog

## 0.1.1

- Documentation and release updates. No API changes.

## 0.1.0

- Initial release.
- `Mocklane.start()` wires a Dio interceptor that rewrites absolute URLs to the
  Mocklane Desktop gateway (`:6625`), with fail-open when Desktop is down.
- `Mocklane.dio` shared client and `Mocklane.interceptor` for existing clients.
- Gateway reachability probe, device metadata headers, and per-client config.
- Device labels default from the platform (`Platform.operatingSystem`, hostname
  on desktop) when the app does not provide them.
- `MocklaneConfig` validates host, port, and probe timeout at construction.
- `Mocklane.log()` posts structured logs with JSON secret masking.
