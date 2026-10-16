import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'demo_app.dart';
import 'demo_controller.dart';

Future<String> previewReply() async =>
    'Streamed first turn: OK.\nStopped a turn and recovered history: violet.';

@Preview(name: 'Core example', size: Size(390, 720))
Widget coreExamplePreview() =>
    CoreExampleApp(controller: DemoController(previewReply));
