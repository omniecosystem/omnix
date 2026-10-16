// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:omnix_core/src/rust/frb_generated.dart';
import 'package:path/path.dart' as p;

Future<void> initializeTestBridge() async {
  if (RustLib.instance.initialized) return;
  // Resolve the selected package, not the runner's working directory. An
  // explicit qualification bridge overrides the local Cargo artifact.
  final fileName = Platform.isWindows
      ? 'omnix_core_bridge.dll'
      : Platform.isMacOS
      ? 'libomnix_core_bridge.dylib'
      : 'libomnix_core_bridge.so';
  final source = await Isolate.resolvePackageUri(
    Uri.parse('package:omnix_core/omnix_core.dart'),
  );
  if (source == null || source.scheme != 'file') {
    throw StateError(
      'Cannot resolve the local Core package for qualification.',
    );
  }
  final library =
      Platform.environment['OMNIX_CORE_TEST_BRIDGE'] ??
      p.join(
        p.dirname(p.dirname(p.fromUri(source))),
        'rust',
        'target',
        'release',
        fileName,
      );
  if (!p.isAbsolute(library) || !File(library).existsSync()) {
    throw StateError(
      'Build a matching standalone Core bridge or set OMNIX_CORE_TEST_BRIDGE to an existing absolute trusted library path. Missing: $library',
    );
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(library));
}
