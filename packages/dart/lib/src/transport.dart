import 'package:http/http.dart' as http;

import 'config.dart';

/// Reachability probe (SRP + DIP via injectable client).
abstract class GatewayProbe {
  Future<bool> isReachable();
}

class HttpGatewayProbe implements GatewayProbe {
  HttpGatewayProbe({
    required this.host,
    required this.port,
    required this.timeout,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String host;
  final int port;
  final Duration timeout;
  final http.Client _client;

  factory HttpGatewayProbe.fromConfig(MocklaneConfig config, {http.Client? client}) {
    return HttpGatewayProbe(
      host: config.host,
      port: config.port,
      timeout: config.probeTimeout,
      client: client,
    );
  }

  @override
  Future<bool> isReachable() async {
    final uri = Uri.parse('http://$host:$port/__mocklane/v1/health');
    try {
      await _client.get(uri).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AlwaysReachableProbe implements GatewayProbe {
  @override
  Future<bool> isReachable() async => true;
}

class NeverReachableProbe implements GatewayProbe {
  @override
  Future<bool> isReachable() async => false;
}
