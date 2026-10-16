// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:native_toolchain_rust/native_toolchain_rust.dart' as rust;
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'litertlm_bundle.dart';
import 'runtime_selection.dart';
import 'windows_crt.dart';
import 'embedding_engine_bundle.dart';
import 'target_support.dart';
import 'android_litertlm_bundle.dart';
import 'android_toolchain.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final defines = coreTargetDefines({
      for (final key in [
        'runtimes',
        'llamacpp',
        'embeddings',
        'embedding_engine',
        'model_installation',
        'litertlm_constraint_assets',
        'litertlm_assets',
        'litertlm_backends',
        input.config.code.targetOS.name,
      ])
        if (input.userDefines[key] != null) key: input.userDefines[key],
    }, input.config.code.targetOS.name);
    final features = selectRuntimeFeatures({
      if (defines['runtimes'] != null) 'runtimes': defines['runtimes'],
      if (defines['llamacpp'] != null) 'llamacpp': defines['llamacpp'],
    });
    final embeddings = defines['embeddings'];
    final installation = defines['model_installation'];
    if (installation != null && installation is! bool) {
      throw ArgumentError('omnix_core.model_installation must be a boolean.');
    }
    if (embeddings != null && embeddings is! bool) {
      throw ArgumentError('omnix_core.embeddings must be a boolean.');
    }
    validateCoreTarget(
      input.config.code.targetOS,
      input.config.code.targetArchitecture,
      features: features,
      legacyEmbeddings: embeddings == true,
    );
    if (input.config.code.targetOS == OS.android) {
      validateAndroidCoreApi(input.config.code.android.targetNdkApi);
    }
    if (installation == true) features.add('model-installation');
    if (embeddings == true) {
      if (!features.contains('litertlm')) {
        throw ArgumentError(
          'Embeddings currently require the litertlm runtime.',
        );
      }
      features.add('litertlm-embeddings');
    }
    final llamaCpp = features.contains('llamacpp');
    final embeddingEngine = defines['embedding_engine'];
    if (embeddingEngine != null && embeddingEngine is! bool) {
      throw ArgumentError('omnix_core.embedding_engine must be a boolean.');
    }
    if (embeddingEngine == true) {
      if (!features.contains('litertlm')) {
        throw ArgumentError('Embedding engine requires the litertlm runtime.');
      }
      features.add('litertlm-embedding-engine');
      if (input.config.code.targetOS == OS.windows) {
        final libraries = await prepareEmbeddingEngineBundle(
          input.outputDirectory,
          sourceArchive: input.userDefines['embedding_engine_archive'] == null
              ? null
              : File(input.userDefines['embedding_engine_archive'] as String),
        );
        for (final library in libraries) {
          output.assets.code.add(
            CodeAsset(
              package: input.packageName,
              name: 'runtime/${library.name}',
              file: library.file,
              linkMode: DynamicLoadingBundled(),
            ),
          );
        }
      }
    }
    final bundleLiteRtLm = includeLiteRtLmAssets(defines['litertlm_assets']);
    if (bundleLiteRtLm &&
        features.contains('litertlm') &&
        input.config.code.targetOS == OS.android) {
      final archive = input.userDefines.path('litertlm_android_archive');
      if (archive == null) {
        throw StateError(
          'Set omnix_core.litertlm_android_archive to the pinned CPU candidate. '
          'See tool/LITERTLM_ANDROID_BUILD.md.',
        );
      }
      output.dependencies.add(archive);
      final libraries = await prepareAndroidLiteRtLmBundle(
        input.outputDirectory,
        sourceArchive: File.fromUri(archive),
        backends: defines['litertlm_backends'],
        includeConstraintProvider: includeAndroidConstraintProvider(
          defines['litertlm_constraint_assets'],
        ),
      );
      for (final library in libraries) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: library.name,
            file: library.file,
            linkMode: DynamicLoadingBundled(),
          ),
        );
      }
    }
    if (bundleLiteRtLm &&
        features.contains('litertlm') &&
        input.config.code.targetOS == OS.windows &&
        input.config.code.targetArchitecture == Architecture.x64) {
      final libraries = await prepareLiteRtLmBundle(
        input.outputDirectory,
        backends: defines['litertlm_backends'],
        sourceArchive: input.userDefines['litertlm_archive'] == null
            ? null
            : File(input.userDefines['litertlm_archive'] as String),
      );
      for (final library in libraries) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: 'runtime/${library.name}',
            file: library.file,
            linkMode: DynamicLoadingBundled(),
          ),
        );
      }
    }
    final environment = <String, String>{
      ...androidToolchainEnvironment(input.config.code),
      if (input.config.code.targetOS == OS.windows)
        ...staticWindowsCrt(Platform.environment),
      if (features.contains('litertlm'))
        'OMNIX_CORE_LITERTLM_HOST_PACKAGING': '1',
      if (llamaCpp && input.config.code.targetOS == OS.windows)
        'CMAKE_GENERATOR_x86_64_pc_windows_msvc': 'NMake Makefiles',
    };
    if (embeddings == true &&
        Platform.isWindows &&
        input.config.code.targetOS == OS.windows) {
      // SentencePiece's protobuf object names need a shorter root than the
      // bridge helper's Temp/frb_native_assets_* directory. Preserve the hook
      // configuration discriminator and use the same official Rust builder.
      final key = sha256
          .convert(utf8.encode(input.outputDirectoryShared.toString()))
          .toString()
          .substring(0, 12);
      final profile = Platform.environment['USERPROFILE'];
      if (profile == null || profile.isEmpty) {
        throw StateError('Windows native embedding build needs USERPROFILE.');
      }
      final cache = Directory.fromUri(
        Directory(profile).uri.resolve('.omnix/c/$key/'),
      );
      await cache.create(recursive: true);
      await rust.RustBuilder(
        assetName: 'src/rust/frb_generated.io.dart',
        cratePath: 'rust',
        enableDefaultFeatures: false,
        features: features,
        extraCargoEnvironmentVariables: environment,
      ).run(
        input: BuildInput({...input.json, 'out_dir_shared': cache.path}),
        output: output,
      );
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      enableDefaultFeatures: false,
      features: features,
      extraCargoEnvironmentVariables: environment,
    ).run(input: input, output: output);
  });
}
