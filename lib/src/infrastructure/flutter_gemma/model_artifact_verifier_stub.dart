// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

bool get supportsModelArtifactVerification => false;

Future<void> verifyModelArtifact({
  required String path,
  required int expectedSize,
  required String expectedSha256,
}) {
  throw UnsupportedError(
    'Model artifact verification is not supported on this platform.',
  );
}
