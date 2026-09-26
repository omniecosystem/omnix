// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:omnix_example/nexus_device_demo.dart';

Future<void> main(List<String> args) async {
  exitCode = await runNexusDeviceDemo(args);
}
