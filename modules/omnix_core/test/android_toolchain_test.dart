// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';
import 'package:hooks/hooks.dart';
import '../hook/android_toolchain.dart';

Future<void> emptyHook(List<String> arguments) =>
    build(arguments, (_, _) async {});

void main() {
  test('non-Android builds keep their existing environment', () async {
    await testCodeBuildHook(
      mainMethod: emptyHook,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      check: (input, _) {
        expect(androidToolchainEnvironment(input.config.code), isEmpty);
      },
    );
  });
  test('uses the declared Android API and requests 16 KiB alignment', () async {
    final directory = await Directory.systemTemp.createTemp('omnix-ndk-test-');
    addTearDown(() => directory.delete(recursive: true));
    final suffix = Platform.isWindows ? '.cmd' : '';
    final compiler = File.fromUri(directory.uri.resolve('clang'));
    await compiler.writeAsString('test fixture, not executed');
    final cc = File.fromUri(
      directory.uri.resolve('aarch64-linux-android31-clang$suffix'),
    );
    final cxx = File.fromUri(
      directory.uri.resolve('aarch64-linux-android31-clang++$suffix'),
    );
    await cc.writeAsString('test fixture, not executed');
    await cxx.writeAsString('test fixture, not executed');
    await testCodeBuildHook(
      mainMethod: emptyHook,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      targetAndroidNdkApi: 31,
      cCompiler: CCompilerConfig(
        compiler: compiler.uri,
        linker: compiler.uri,
        archiver: compiler.uri,
      ),
      check: (input, _) {
        final environment = androidToolchainEnvironment(input.config.code);
        expect(environment['CC_aarch64_linux_android'], cc.path);
        expect(environment['CXX_aarch64_linux_android'], cxx.path);
        expect(
          environment['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'],
          cc.path,
        );
        expect(environment['RUSTFLAGS'], contains('max-page-size=16384'));
      },
    );
  });
  test('fails clearly when the selected NDK lacks a declared API', () async {
    final directory = await Directory.systemTemp.createTemp(
      'omnix-ndk-missing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final compiler = directory.uri.resolve('clang');
    await File.fromUri(compiler).writeAsString('test fixture, not executed');
    await testCodeBuildHook(
      mainMethod: emptyHook,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      targetAndroidNdkApi: 31,
      cCompiler: CCompilerConfig(
        compiler: compiler,
        linker: compiler,
        archiver: compiler,
      ),
      check: (input, _) {
        expect(
          () => androidToolchainEnvironment(input.config.code),
          throwsStateError,
        );
      },
    );
  });
}
