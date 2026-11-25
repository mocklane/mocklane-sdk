import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'demo_runner.dart';
import 'demo_scenarios.dart';

void main() {
  MocklaneBootstrap.start();
  runApp(const MocklaneSampleApp());
}

class MocklaneSampleApp extends StatelessWidget {
  const MocklaneSampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mocklane',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F4A)),
        useMaterial3: true,
      ),
      home: const SampleHome(),
    );
  }
}

class SampleHome extends StatefulWidget {
  const SampleHome({super.key});

  @override
  State<SampleHome> createState() => _SampleHomeState();
}

class _SampleHomeState extends State<SampleHome> {
  String _out = 'Ready.';
  bool _busy = false;

  String _pathLabel(DemoScenario scenario) {
    if (scenario.kind == 'sdk_log') return 'POST /__mocklane/v1/log';
    final uri = Uri.parse(scenario.url ?? '');
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    return '${scenario.method} ${uri.path}$query';
  }

  Future<void> _runOne(DemoScenario scenario) async {
    setState(() {
      _busy = true;
      _out = 'Running ${scenario.id} …';
    });
    final result = await DemoRunner.run(scenario);
    setState(() {
      _busy = false;
      _out = '[${result.id}] ${result.ok ? 'OK' : 'FAIL'}\n${result.detail}';
    });
  }

  Future<void> _runAll() async {
    setState(() {
      _busy = true;
      _out = 'Running all scenarios …\n';
    });
    final lines = <String>[];
    await DemoRunner.runAll(onProgress: (_, result) {
      lines.add(
        '[${result.id}] ${result.ok ? 'OK' : 'FAIL'} status=${result.status ?? '—'}',
      );
      setState(() => _out = lines.join('\n'));
    });
    setState(() {
      _busy = false;
      _out = '${lines.join('\n')}\n\n=== Run all complete ===';
    });
  }

  @override
  void dispose() {
    MocklaneBootstrap.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = MocklaneBootstrap.isEnabled;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mocklane SDK demo',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Same scenario catalog as web, Android, iOS, and Swift CLI. '
                'Desktop Listening on :6625 required.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: !_busy && enabled ? _runAll : null,
                    child: const Text('Run all'),
                  ),
                  OutlinedButton(
                    onPressed: !_busy ? () => setState(() => _out = 'Ready.') : null,
                    child: const Text('Clear output'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: DemoScenarios.all.length,
                  itemBuilder: (context, index) {
                    final scenario = DemoScenarios.all[index];
                    return ListTile(
                      title: Text('${scenario.id} ${scenario.label}'),
                      subtitle: Text(
                        _pathLabel(scenario),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: !_busy && enabled
                            ? () => _runOne(scenario)
                            : null,
                        child: const Text('Run'),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                height: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF122018),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    enabled
                        ? _out
                        : 'Release build — Mocklane disabled.',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFD7F5E4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
