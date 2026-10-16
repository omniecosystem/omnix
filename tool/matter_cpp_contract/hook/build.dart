// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'omnix_matter_contract',
      assetName: 'contract',
      language: Language.cpp,
      std: 'c++17',
      flags: [if (input.config.code.targetOS == OS.windows) '/EHsc'],
      sources: [
        '../../modules/omnix_nexus/rust/backend/native/matter_cpp/controller.cpp',
        'native/contract.cpp',
      ],
      includes: [
        'native/doubles',
        '../../modules/omnix_nexus/rust/backend/native/matter_cpp',
      ],
    ).run(input: input, output: output);
  });
}
