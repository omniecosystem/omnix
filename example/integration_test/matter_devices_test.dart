import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_example/features/nexus/presentation/pages/matter_host_screen.dart';
import 'package:omnix_example/features/nexus/presentation/widgets/matter_host_panel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'main example Devices UI controls and reopens its native host',
    (tester) async {
      const address = String.fromEnvironment('MATTER_LIGHT_ADDRESS');
      const commission = bool.fromEnvironment('MATTER_COMMISSION');
      expect(address, isNotEmpty);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MatterHostScreen())),
      );
      await tester.pumpAndSettle();
      final model = tester
          .widget<MatterHostPanel>(find.byType(MatterHostPanel))
          .model;
      await tester.enterText(find.byType(TextField), address);
      if (commission) {
        await tester.tap(find.text('Commission a fresh test light'));
      }
      await tester.tap(find.text('Allow commands to my test light'));
      await tester.pumpAndSettle();
      Future<void> wait() async {
        final watch = Stopwatch()..start();
        while (model.busy && watch.elapsed < const Duration(minutes: 3)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(model.busy, isFalse);
        expect(model.error, isNull);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Connect'));
      await wait();
      expect(model.connected, isTrue);
      for (final (label, on) in [('Turn on', true), ('Turn off', false)]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await wait();
        expect(model.on, on);
      }
      await tester.tap(find.text('Disconnect'));
      await wait();
      expect(model.connected, isFalse);
      if (commission) {
        await tester.ensureVisible(find.text('Commission a fresh test light'));
        await tester.tap(find.text('Commission a fresh test light'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await wait();
      expect(model.on, isFalse);
      await model.disconnect();
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
