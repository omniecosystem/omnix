// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:code_assets/code_assets.dart';

void validateAndroidCoreApi(int api) {
  if (api < 31) {
    throw UnsupportedError('This Android LiteRT-LM candidate requires API 31+.');
  }
}

// Runtime flags describe desired components, not proof of native delivery.
// Keep this guard aligned with the Rust bridge's execution restrictions.
void validateCoreTarget(
  OS os,
  Architecture architecture, {
  List<String> features = const [],
  bool legacyEmbeddings = false,
}) {
  if (os == OS.windows && architecture == Architecture.x64) return;
  if (os == OS.android &&
      architecture == Architecture.arm64 &&
      features.length == 1 &&
      features.single == 'litertlm' &&
      !legacyEmbeddings) {
    return;
  }
  throw UnsupportedError(
    'Omnix Core native execution and runtime delivery currently support '
    'Windows x64, or Android arm64 with explicitly selected litertlm and '
    'embeddings: false. Requested target: ${os.name}/${architecture.name}. '
    'Android needs the pinned CPU C-API archive, API 31+, and extracted native '
    'libraries; llama.cpp and legacy tensor encoders remain unqualified there. '
    'See doc/ANDROID_NATIVE_READINESS.md in the Omnix repository.',
  );
}
