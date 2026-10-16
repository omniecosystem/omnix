import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'dart:io';
import 'package:code_assets/code_assets.dart';
import '../modules/omnix_core/hook/litertlm_bundle.dart';
import '../modules/omnix_core/hook/windows_crt.dart';
import '../modules/omnix_core/hook/embedding_engine_bundle.dart';
import '../modules/omnix_core/hook/android_toolchain.dart';
import '../modules/omnix_core/hook/android_litertlm_bundle.dart';
import '../modules/omnix_core/hook/target_support.dart';
import 'runtime_selection.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final target = input.userDefines[input.config.code.targetOS.name];
    final runtimes = selectRootRuntimes(input.userDefines['runtimes'], target);
    final knowledge = target is Map && target.containsKey('knowledge')
        ? target['knowledge']
        : input.userDefines['knowledge'];
    if (knowledge != null && knowledge is! bool) {
      throw ArgumentError('omnix.knowledge must be a boolean.');
    }
    if (knowledge == true && !runtimes.contains('litertlm')) {
      throw ArgumentError('Local Knowledge currently requires litertlm.');
    }
    final agent = target is Map && target.containsKey('agent')
        ? target['agent']
        : input.userDefines['agent'];
    if (agent != null && agent is! bool) {
      throw ArgumentError('omnix.agent must be a boolean.');
    }
    final workflow = target is Map && target.containsKey('workflow')
        ? target['workflow']
        : input.userDefines['workflow'];
    if (workflow != null && workflow is! bool) {
      throw ArgumentError('omnix.workflow must be a boolean.');
    }
    if (workflow == true && agent != true) {
      throw ArgumentError(
        'Local Workflow uses the authorized agent tool registry; select omnix.agent: true.',
      );
    }
    if (agent == true && !runtimes.contains('litertlm')) {
      throw ArgumentError('The native agent currently requires litertlm.');
    }
    final android = input.config.code.targetOS == OS.android;
    final androidLibrary = android
        ? selectAndroidLiteRtLmLibrary(
            target is Map ? target['litertlm_library'] : null,
          )
        : null;
    if (runtimes.isNotEmpty && android) {
      validateAndroidCoreApi(input.config.code.android.targetNdkApi);
      if (input.config.code.targetArchitecture != Architecture.arm64 ||
          runtimes.length != 1 ||
          runtimes.single != 'litertlm') {
        throw UnsupportedError(
          'Experimental root Android composition requires arm64 and litertlm.',
        );
      }
    }
    if (runtimes.isNotEmpty &&
        !android &&
        (input.config.code.targetOS != OS.windows ||
            input.config.code.targetArchitecture != Architecture.x64)) {
      throw UnsupportedError(
        'Root session packaging is qualified only for Windows x64. Select no root runtimes on other targets; standalone modules remain available.',
      );
    }
    if (runtimes.contains('litertlm')) {
      final assets = target is Map && target.containsKey('litertlm_assets')
          ? target['litertlm_assets']
          : input.userDefines['litertlm_assets'];
      final owner = selectLiteRtLmAssetOwner(assets, android: android);
      // An app importing both bindings must choose one asset owner. Both native
      // registries resolve these identical pinned DLLs beside their own bridge.
      if (owner == 'self' && android) {
        final archive = input.userDefines.path('litertlm_android_archive');
        if (archive == null) {
          throw StateError(
            'Set omnix.litertlm_android_archive to the pinned CPU archive.',
          );
        }
        output.dependencies.add(archive);
        final libraries = await prepareAndroidLiteRtLmBundle(
          input.outputDirectory,
          sourceArchive: File.fromUri(archive),
          backends: target is Map && target.containsKey('litertlm_backends')
              ? target['litertlm_backends']
              : input.userDefines['litertlm_backends'],
          includeConstraintProvider: includeAndroidConstraintProvider(
            target is Map ? target['litertlm_constraint_assets'] : null,
          ),
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
      } else if (owner == 'self') {
        final archive = input.userDefines.path('litertlm_archive');
        final cachedArchive =
            Platform.environment['OMNIX_CORE_LITERTLM_ARCHIVE'];
        final libraries = await prepareLiteRtLmBundle(
          input.outputDirectory,
          backends: target is Map
              ? target['litertlm_backends']
              : input.userDefines['litertlm_backends'],
          sourceArchive: archive != null
              ? File.fromUri(archive)
              : cachedArchive == null
              ? null
              : File(cachedArchive),
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
        if (knowledge == true) {
          final archive = input.userDefines.path('embedding_engine_archive');
          final libraries = await prepareEmbeddingEngineBundle(
            input.outputDirectory,
            sourceArchive: archive == null ? null : File.fromUri(archive),
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
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      enableDefaultFeatures: false,
      features: [
        'flutter-bridge',
        for (final runtime in runtimes) 'core-$runtime',
        if (knowledge == true) 'knowledge-local',
        if (agent == true) 'agent',
        if (workflow == true) 'workflow-local',
      ],
      extraCargoEnvironmentVariables: {
        if (android) ...androidToolchainEnvironment(input.config.code),
        if (input.config.code.targetOS == OS.windows)
          ...staticWindowsCrt(Platform.environment),
        if (runtimes.contains('litertlm'))
          'OMNIX_CORE_LITERTLM_HOST_PACKAGING': '1',
        if (android && runtimes.contains('litertlm'))
          'OMNIX_CORE_LITERTLM_ANDROID_LIBRARY': androidLibrary!,
        if (runtimes.contains('llamacpp'))
          'CMAKE_GENERATOR_x86_64_pc_windows_msvc': 'NMake Makefiles',
      },
    ).run(input: input, output: output);
  });
}
