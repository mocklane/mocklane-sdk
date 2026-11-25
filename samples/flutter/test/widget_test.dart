import 'package:flutter_test/flutter_test.dart';
import 'package:mocklane_flutter_sample/demo_scenarios.dart';
import 'package:mocklane_flutter_sample/main.dart';

void main() {
  testWidgets('sample home renders scenario list and run all', (tester) async {
    await tester.pumpWidget(const MocklaneSampleApp());
    expect(find.text('Mocklane SDK demo'), findsOneWidget);
    expect(find.text('Run all'), findsOneWidget);
    expect(find.text('${DemoScenarios.all.first.id} ${DemoScenarios.all.first.label}'), findsOneWidget);
    expect(DemoScenarios.all.length, 14);
  });
}
