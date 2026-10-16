// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../rust/frb_generated.dart' show RustLib;

Future<void>? _initialization;

/// Shares native bridge initialization across module adapters in this isolate.
Future<void> ensureRustInitialized() {
  final pending = _initialization;
  if (pending != null) return pending;
  if (RustLib.instance.initialized) return Future<void>.value();
  return _initialization ??= RustLib.init();
}
