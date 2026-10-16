import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_core_example/demo_app.dart';
import 'package:omnix_core_example/demo_controller.dart';
import 'package:omnix_core_example/native_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('packaged example executes its own native module', (
    tester,
  ) async {
    final controller = DemoController(runNativeDemo);
    await tester.pumpWidget(CoreExampleApp(controller: controller));
    await tester.tap(find.text('Run local demo'));
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (controller.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    expect(controller.busy, isFalse, reason: 'Native operation timed out');
    expect(controller.error, isNull);
    expect(controller.result, isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(controller.result!), findsOneWidget);
  });
}
