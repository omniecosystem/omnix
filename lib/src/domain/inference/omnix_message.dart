// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// The participant responsible for one conversation message.
enum OmnixMessageRole { user, assistant }

/// The semantic purpose of a conversation message.
enum OmnixMessageKind { text, toolResponse, toolCall, systemInfo, thinking }

/// A provider-neutral snapshot of one message in a model conversation.
///
/// This value represents replayable session history. It does not prescribe
/// where or how a host persists that history.
final class OmnixMessage {
  OmnixMessage({
    required this.text,
    required this.role,
    this.kind = OmnixMessageKind.text,
    this.toolName,
    Uint8List? imageBytes,
    List<Uint8List> images = const [],
    Uint8List? audioBytes,
  }) : imageBytes = _copyBytes(imageBytes),
       images = List.unmodifiable(images.map(Uint8List.fromList)),
       audioBytes = _copyBytes(audioBytes);

  /// Creates a plain text message.
  factory OmnixMessage.text({
    required String text,
    required OmnixMessageRole role,
  }) => OmnixMessage(text: text, role: role);

  final String text;
  final OmnixMessageRole role;
  final OmnixMessageKind kind;
  final String? toolName;
  final Uint8List? imageBytes;
  final List<Uint8List> images;
  final Uint8List? audioBytes;

  bool get hasImage => imageBytes != null || images.isNotEmpty;
  bool get hasAudio => audioBytes != null;
}

Uint8List? _copyBytes(Uint8List? bytes) =>
    bytes == null ? null : Uint8List.fromList(bytes);
