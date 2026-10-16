import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'demo_app.dart';
import 'demo_controller.dart';

Future<String> previewReply() async =>
    'Public answer\nSource: Preview\n\nPrivate request refused.';

@Preview(name: 'Nexus example', size: Size(390, 720))
Widget nexusExamplePreview() =>
    NexusExampleApp(controller: DemoController(previewReply));
