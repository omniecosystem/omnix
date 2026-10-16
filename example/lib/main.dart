import 'package:flutter/material.dart';
import 'features/workflow/data/services/background_workflow.dart';
import 'features/home/presentation/services/tool_approval.dart';
import 'package:omnix_example/features/home/presentation/pages/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OmnixNativeExample());
}

@pragma('vm:entry-point')
void workflowBackgroundMain() => runBackgroundWorkflow();

class OmnixNativeExample extends StatelessWidget {
  const OmnixNativeExample({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: exampleNavigatorKey,
    title: 'Omnix',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00E5FF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF10171C),
      useMaterial3: true,
    ),
    home: const HomeScreen(),
  );
}
