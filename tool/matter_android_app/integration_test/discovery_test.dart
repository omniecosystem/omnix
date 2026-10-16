import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_matter_android_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android NSD sees the stored fabric operational service',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();
      const channel = MethodChannel('omnix/matter-qualification');
      final result = await channel
          .invokeMapMethod<String, dynamic>('qualifyDiscovery')
          .timeout(const Duration(seconds: 40));
      // Include bounded diagnostic metadata in a failure without logging keys.
      expect(result?['targetSeen'], isTrue, reason: 'NSD probe: $result');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
