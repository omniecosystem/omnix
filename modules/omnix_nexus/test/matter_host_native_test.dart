// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:omnix_nexus/src/rust/frb_generated.dart' show RustLib;
import 'package:test/test.dart';

void main() {
  final dll = Platform.environment['OMNIX_MATTER_HOST_DLL'];
  final bundle = Platform.environment['OMNIX_MATTER_HOST_BUNDLE'];
  test(
    'Dart FRB host session commands and reads the disposable light',
    () async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(dll!));
      final storage = await Directory.systemTemp.createTemp(
        'omnix-frb-matter-',
      );
      OmnixMatterHost? host;
      try {
        host = await OmnixMatterHost.openWindowsFixture(
          bundle: bundle!,
          storage: storage.path,
        );
        for (final on in [true, false]) {
          await host.setOnOff(on: on);
          expect(await host.readOnOff(), on);
        }
        await host.close();
        await host.close();
        await expectLater(host.readOnOff(), throwsStateError);
      } finally {
        try {
          await host?.close();
        } finally {
          try {
            RustLib.dispose();
          } finally {
            await storage.delete(recursive: true);
          }
        }
      }
    },
    skip: !Platform.isWindows || dll == null || bundle == null
        ? 'Requires explicitly built matter-process DLL and verified runtime bundle.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
