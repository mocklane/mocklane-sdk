// URL rewrite (SRP) — matches Desktop `url_map` origin-prefixed form.

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
  // Fragment stripped (gateway U17).
  final embedded = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path$query';
  return 'http://$host:$port/$embedded';
}

bool isGatewayUrl(
  String input, {
  String host = '127.0.0.1',
  int port = 6625,
}) {
  final uri = Uri.tryParse(input);
  if (uri == null) return false;
  return uri.host == host && uri.port == port;
}
