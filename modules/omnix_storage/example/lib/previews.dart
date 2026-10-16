import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'demo_app.dart';
import 'demo_controller.dart';

Future<String> previewReply() async =>
    'Snapshot recovered through a fresh connection.';

@Preview(name: 'Storage example', size: Size(390, 720))
Widget storageExamplePreview() =>
    StorageExampleApp(controller: DemoController(previewReply));
