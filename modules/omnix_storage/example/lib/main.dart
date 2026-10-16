import 'package:flutter/material.dart';

import 'demo_app.dart';
import 'demo_controller.dart';
import 'native_demo.dart';

void main() =>
    runApp(StorageExampleApp(controller: DemoController(runNativeDemo)));
