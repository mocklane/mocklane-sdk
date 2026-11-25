// URL rewrite — matches Desktop `url_map` origin-prefixed form.

String rewriteToGateway(
  String input, {
  String host = '127.0.0.1',
  int port = 6625,
}) {
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return input;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return input;
  }
  if (isGatewayUrl(input, host: host, port: port)) {
    return input;
  }

  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  // Userinfo is dropped on purpose: Desktop rejects credentials embedded in
  // the origin (U08). The fragment is stripped too (gateway U17).
  // `Uri.host` strips IPv6 brackets, so re-add them or the embedded origin is
  // not a valid URL.
  final embeddedHost = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final embeddedPort = uri.hasPort ? ':${uri.port}' : '';
  final embedded = '${uri.scheme}://$embeddedHost$embeddedPort$path$query';
  return 'http://$host:$port/$embedded';
}

bool isGatewayUrl(
  String input, {
  String host = '127.0.0.1',
  int port = 6625,
}) {
  final uri = Uri.tryParse(input);
  if (uri == null) return false;
  // `Uri.port` resolves the scheme default (80/443), so a gateway URL that
  // omits an explicit port still matches. `Uri.host` keeps IPv6 addresses
  // unbracketed while the configured host may be bracketed; compare both
  // forms lowered.
  return _normalizeHost(uri.host) == _normalizeHost(host) && uri.port == port;
}

String _normalizeHost(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.length > 1 && trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}
