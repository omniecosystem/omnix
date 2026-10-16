import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_matter_android_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android JNI controller starts with explicit test trust', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    const channel = MethodChannel('omnix/matter-qualification');
    final result = await channel.invokeMapMethod<String, dynamic>(
      'qualifyLifecycle',
    );
    expect(result?['jniLoaded'], isTrue);
    expect(result?['fabricIndex'], greaterThan(0));
    expect(result?['testTrustConfigured'], isTrue);
    final repeated = await channel.invokeMapMethod<String, dynamic>(
      'qualifyLifecycle',
    );
    expect(result?['ownerId'], isNotEmpty);
    expect(repeated?['ownerId'], result?['ownerId']);
    expect(repeated?['fabricIndex'], result?['fabricIndex']);
  });
}
