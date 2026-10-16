// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_example/features/nexus/presentation/widgets/matter_host_panel.dart';

@Preview(name: 'Matter host · disconnected', size: Size(420, 820))
Widget matterHostPreview() => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(
    body: MatterHostPanel(
      model: MatterHostModel(
        (_, _) async => throw StateError('Preview has no native controller'),
      ),
      backend: 'Android · C++ SDK / JNI',
      inputLabel: 'Software-light laptop LAN IP',
      android: true,
    ),
  ),
);
