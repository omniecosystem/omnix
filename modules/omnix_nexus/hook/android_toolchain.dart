// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:code_assets/code_assets.dart';

// Resolve NDK compilers for the application's declared API and target ABI.
// The selected paths apply only to the Rust build process.
Map<String, String> androidToolchainEnvironment(CodeConfig code) {
  if (code.targetOS != OS.android) return {};
  final (rustTriple, ndkTriple) = switch (code.targetArchitecture) {
    Architecture.arm64 => ('aarch64_linux_android', 'aarch64-linux-android'),
    Architecture.arm => ('armv7_linux_androideabi', 'armv7a-linux-androideabi'),
    Architecture.x64 => ('x86_64_linux_android', 'x86_64-linux-android'),
    Architecture.ia32 => ('i686_linux_android', 'i686-linux-android'),
    _ => throw UnsupportedError('Unsupported Android Rust architecture.'),
  };
  final compiler = code.cCompiler?.compiler;
  if (compiler == null) throw StateError('Android needs an NDK compiler.');
  final api = code.android.targetNdkApi;
  final suffix = Platform.isWindows ? '.cmd' : '';
  final cc = File.fromUri(compiler.resolve('$ndkTriple$api-clang$suffix'));
  final cxx = File.fromUri(compiler.resolve('$ndkTriple$api-clang++$suffix'));
  if (!cc.existsSync() || !cxx.existsSync()) {
    throw StateError('The selected NDK lacks Android API $api compilers.');
  }
  return {
    'CC_$rustTriple': cc.path,
    'CXX_$rustTriple': cxx.path,
    'CARGO_TARGET_${rustTriple.toUpperCase()}_LINKER': cc.path,
    'RUSTFLAGS': '-C link-arg=-Wl,-z,max-page-size=16384',
  };
}
