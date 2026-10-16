import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/device_tools.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native approval cancellation releases the host', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Approval qualification'))),
    );
    await tester.runAsync(() async {
      const host = ExampleDeviceTools();
      final pending = host.tools.last.execute(
        OmnixToolRequest.fromJson({
          'requestId': 'cancel-test',
          'toolName': 'host_open_app',
          'arguments': {'application': 'settings'},
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await host.cancelPending();
      expect(await pending, {'status': 'denied'});
    });
  });
  testWidgets('native user approval outcome', (tester) async {
    const action = String.fromEnvironment('OMNIX_APPROVAL_ACTION');
    if (action != 'deny' && action != 'open') {
      throw StateError(
        'Set OMNIX_APPROVAL_ACTION=deny or open; interact with the native dialog.',
      );
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Approval qualification'))),
    );
    await tester.runAsync(() async {
      const host = ExampleDeviceTools();
      try {
        final result = await host.tools.last.execute(
          OmnixToolRequest.fromJson({
            'requestId': 'approval-test',
            'toolName': 'host_open_app',
            'arguments': {'application': 'settings'},
          }),
        );
        expect(result, {'status': action == 'open' ? 'opened' : 'denied'});
      } finally {
        await host.cancelPending();
      }
    });
  });
}
