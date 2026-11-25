import 'package:dio/dio.dart';
import 'package:mocklane/mocklane.dart';

import 'bootstrap.dart';
import 'demo_scenarios.dart';

class DemoResult {
  const DemoResult({
    required this.id,
    required this.ok,
    this.status,
    required this.detail,
  });

  final String id;
  final bool ok;
  final int? status;
  final String detail;
}

class DemoRunner {
  static Future<DemoResult> run(DemoScenario scenario) async {
    if (!MocklaneBootstrap.isEnabled) {
      return DemoResult(
        id: scenario.id,
        ok: false,
        detail: 'Mocklane disabled in release builds.',
      );
    }

    if (scenario.kind == 'sdk_log') {
      final level = switch (scenario.logLevel) {
        'warn' => LogLevel.warn,
        'error' => LogLevel.error,
        'debug' => LogLevel.debug,
        _ => LogLevel.info,
      };
      Mocklane.log(scenario.logMessage ?? '', level: level, tag: scenario.logTag);
      return DemoResult(
        id: scenario.id,
        ok: true,
        detail: 'SDK_LOG ${scenario.logLevel} tag=${scenario.logTag}',
      );
    }

    final url = scenario.url;
    if (url == null) {
      return DemoResult(id: scenario.id, ok: false, detail: 'missing url');
    }

    try {
      final isBinary = scenario.responseKind == 'binary';
      final options = Options(
        method: scenario.method,
        headers: scenario.headers,
        responseType: isBinary ? ResponseType.bytes : ResponseType.plain,
        validateStatus: (_) => true,
      );

      dynamic data;
      if (scenario.body != null) {
        if (scenario.contentType == 'application/x-www-form-urlencoded') {
          data = scenario.body;
        } else {
          data = scenario.body;
        }
      }

      final res = await Mocklane.dio.request<dynamic>(
        url,
        data: data,
        options: options.copyWith(
          contentType: scenario.contentType,
        ),
      );

      final status = res.statusCode ?? -1;
      final detail = isBinary
          ? '${(res.data as List<int>).length} bytes'
          : res.data.toString().substring(
              0,
              res.data.toString().length.clamp(0, 600),
            );

      return DemoResult(
        id: scenario.id,
        ok: (status >= 200 && status < 300) || scenario.id == 'S12',
        status: status,
        detail: 'status $status\nTraffic: FORWARD ${scenario.method} …\n\n$detail',
      );
    } catch (e) {
      return DemoResult(id: scenario.id, ok: false, detail: 'error: $e');
    }
  }

  static Future<List<DemoResult>> runAll({
    void Function(DemoScenario scenario, DemoResult result)? onProgress,
  }) async {
    final results = <DemoResult>[];
    for (final scenario in DemoScenarios.all) {
      final result = await run(scenario);
      results.add(result);
      onProgress?.call(scenario, result);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return results;
  }
}
