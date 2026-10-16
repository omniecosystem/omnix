// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'component_selection.dart';
import 'android_toolchain.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final features = selectNexusFeatures(
      {
        'protocols': input.userDefines['protocols'],
        if (input.userDefines['android'] != null)
          'android': input.userDefines['android'],
        if (input.userDefines['windows'] != null)
          'windows': input.userDefines['windows'],
        if (input.userDefines['experimental_matter'] != null)
          'experimental_matter': input.userDefines['experimental_matter'],
        if (input.userDefines['matter_backend'] != null)
          'matter_backend': input.userDefines['matter_backend'],
      },
      windows: input.config.code.targetOS == OS.windows,
      android: input.config.code.targetOS == OS.android,
    );
    final experimentalMatter = features.contains('matter');
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      enableDefaultFeatures: false,
      features: features,
      // The simulator backend uses a debug native build to limit compilation
      // cost. A2A and platform-host-only selections use release native builds.
      buildMode: experimentalMatter == true
          ? FlutterRustBridgeBuildMode.debug
          : FlutterRustBridgeBuildMode.release,
      extraCargoEnvironmentVariables: {
        ...androidToolchainEnvironment(input.config.code),
        if (experimentalMatter) ...{
          'CARGO_BUILD_JOBS': '2',
          'CARGO_PROFILE_DEV_DEBUG': '0',
        },
      },
    ).run(input: input, output: output);
  });
}
