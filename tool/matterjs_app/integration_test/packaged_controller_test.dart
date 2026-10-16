import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_matterjs_app/main.dart';
import 'package:omnix_matterjs_app/packaged_controller_check.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'bundled controller commissions, controls and restores its fabric',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      final milestones = await tester.runAsync(checkPackagedController);
      expect(milestones, hasLength(4));
      expect(milestones![1], contains('On/Off commands and reads succeeded'));
      expect(milestones[2], contains('without recommissioning'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
