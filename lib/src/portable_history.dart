import 'dart:convert';

import 'interaction_input.dart';

/// The kind of a host-recorded historical observation.
enum OmnixHistoryObservationKind { call, result, note }

/// Historical content without execution permission or pending-call state.
final class OmnixHistoryObservation {
  /// Creates recorded context for a past interaction.
  const OmnixHistoryObservation({
    required this.kind,
    required this.text,
    this.name,
  });
  final OmnixHistoryObservationKind kind;
  final String? name;
  final String text;
}

/// A historical user input, optional visible reply, and recorded observations.
final class OmnixHistoryTurn {
  /// Creates semantic context without reconstructing runtime-owned state.
  OmnixHistoryTurn({
    required List<OmnixInteractionInput> input,
    this.answer,
    List<OmnixHistoryObservation> observations = const [],
  }) : input = List.unmodifiable(input),
       observations = List.unmodifiable(observations);
  final List<OmnixInteractionInput> input;
  final String? answer;
  final List<OmnixHistoryObservation> observations;
}

/// Encodes semantic history for Rust validation and import into a fresh session.
///
/// This is not a native checkpoint, KV cache, or grant to execute past calls.
/// Rust validates media, bounds and backend support. Missing replies remain
/// explicitly missing rather than being represented as generated answers.
String encodeOmnixHistory(List<OmnixHistoryTurn> turns) => jsonEncode({
  'version': 3,
  'turns': [
    for (final turn in turns)
      {
        'input': [
          for (final part in turn.input)
            switch (part.kind) {
              OmnixInteractionInputKind.text => {
                'type': 'text',
                'text': part.text!,
              },
              OmnixInteractionInputKind.image => {
                'type': 'image',
                'blob': base64Encode(part.bytes),
              },
              OmnixInteractionInputKind.audio => {
                'type': 'audio',
                'blob': base64Encode(part.bytes),
              },
            },
        ],
        'answer': turn.answer,
        'observations': [
          for (final observation in turn.observations)
            {
              'kind': observation.kind.name,
              'name': observation.name,
              'text': observation.text,
            },
        ],
      },
  ],
});
