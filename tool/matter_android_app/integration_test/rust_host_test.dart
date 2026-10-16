import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_matter_android_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Rust host controls the retained Android SDK controller',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();
      const channel = MethodChannel('omnix/matter-qualification');
      final before = await channel.invokeMapMethod<String, dynamic>(
        'qualifyLifecycle',
      );
      final result = await channel.invokeMapMethod<String, dynamic>(
        'qualifyRustControl',
      );
      expect(result?['rustOnOffVerified'], isTrue);
      expect(result?['nativeOwnerRetained'], isTrue);
      expect(result?['ownerId'], before?['ownerId']);
      expect(result?['fabricIndex'], before?['fabricIndex']);
      expect(
        result?['trustLookups'],
        0,
        reason: 'Rust control must not recommission',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
