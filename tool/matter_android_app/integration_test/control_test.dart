import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_matter_android_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android commissions or restores and controls a software light',
    (tester) async {
      const address = String.fromEnvironment('MATTER_LIGHT_ADDRESS');
      const commission = bool.fromEnvironment('MATTER_COMMISSION');
      expect(address, isNotEmpty, reason: 'Provide the software light LAN IP');
      app.main();
      await tester.pumpAndSettle();
      const channel = MethodChannel('omnix/matter-qualification');
      final result = await channel
          .invokeMapMethod<String, dynamic>('qualifyControl', {
            'address': address,
            'commission': commission,
          })
          .timeout(const Duration(minutes: 5));
      expect(result?['onOffVerified'], isTrue);
      expect(result?['commissionedNow'], commission);
      expect(result?['fabricIndex'], greaterThan(0));
      if (commission) {
        expect(result?['trustLookups'], greaterThan(0));
      } else {
        // Restoration must use the saved fabric, not quietly pair again.
        expect(result?['trustLookups'], 0);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
