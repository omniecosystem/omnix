import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/device_tools.dart';
import 'package:omnix_example/features/home/presentation/pages/home_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android Home agent works without Knowledge',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final expected = await tester.runAsync(
        () => const ExampleDeviceTools().tools.first.execute(
          OmnixToolRequest.fromJson({
            'requestId': 'home-preflight',
            'toolName': 'host_device_info',
            'arguments': <String, dynamic>{},
          }),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      for (
        var i = 0;
        i < 100 && find.byTooltip('Conversation options').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      expect(find.text('Agent tools'), findsOneWidget);
      await tester.tap(find.text('Agent tools'));
      await tester.pump();
      await tester.tap(find.byTooltip('Close conversation options'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Call host_device_info and tell me this device model exactly. Do not guess.',
      );
      await tester.tap(find.text('Send'));
      final deviceModel = (expected as Map)['model'] as String;
      for (
        var i = 0;
        i < 240 && find.textContaining(deviceModel).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump();
      }
      expect(find.textContaining(deviceModel), findsWidgets);
      expect(find.text('Tool activity'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
