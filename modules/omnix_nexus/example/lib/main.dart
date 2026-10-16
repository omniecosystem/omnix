import 'package:flutter/material.dart';

import 'demo_app.dart';
import 'demo_controller.dart';
import 'local_demo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(NexusExampleApp(controller: DemoController(runLocalDemo)));
}
