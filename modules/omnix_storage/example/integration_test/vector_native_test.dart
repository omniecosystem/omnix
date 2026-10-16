import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_storage_example/demo_app.dart';
import 'package:omnix_storage_example/demo_controller.dart';
import 'package:omnix_storage_example/vector_native_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('packaged Qdrant survives reopen and enforces filtering', (
    tester,
  ) async {
    final controller = DemoController(runVectorNativeDemo);
    await tester.pumpWidget(StorageExampleApp(controller: controller));
    await tester.tap(find.text('Run local demo'));
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (controller.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    expect(
      controller.busy,
      isFalse,
      reason: 'Native vector operation timed out',
    );
    expect(controller.error, isNull);
    expect(controller.result, contains('durable deletion passed'));
    await tester.pumpAndSettle();
    expect(find.text(controller.result!), findsOneWidget);
  });
}
