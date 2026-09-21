// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../inference/omnix_message.dart';

/// Token capacity reserved for one model request.
final class OmnixContextBudget {
  const OmnixContextBudget({
    required this.contextWindowTokens,
    required this.reservedOutputTokens,
  }) : assert(contextWindowTokens > 0),
       assert(reservedOutputTokens >= 0),
       assert(reservedOutputTokens < contextWindowTokens);

  final int contextWindowTokens;
  final int reservedOutputTokens;

  int get availableInputTokens => contextWindowTokens - reservedOutputTokens;
}

/// Estimates token usage without exposing a provider tokenizer.
abstract interface class OmnixTokenEstimator {
  int estimateText(String text);

  int estimateMessage(OmnixMessage message);
}

/// The replayable history selected for an active model context.
final class OmnixContextSelection {
  OmnixContextSelection({
    required List<OmnixMessage> messages,
    required this.estimatedInputTokens,
    required this.omittedMessageCount,
  }) : messages = List.unmodifiable(messages);

  final List<OmnixMessage> messages;

  /// Estimated tokens for selected history and any reserved additional input.
  final int estimatedInputTokens;
  final int omittedMessageCount;

  bool get wasTrimmed => omittedMessageCount > 0;
}

/// Selects active replay history while durable history remains untouched.
abstract interface class OmnixContextPolicy {
  OmnixContextSelection select(
    List<OmnixMessage> history, {
    List<OmnixMessage> additionalMessages = const [],
  });
}

/// Indicates that mandatory context alone cannot fit the configured budget.
final class OmnixContextOverflowException implements Exception {
  const OmnixContextOverflowException({
    required this.requiredTokens,
    required this.availableTokens,
  });

  final int requiredTokens;
  final int availableTokens;

  @override
  String toString() =>
      'OmnixContextOverflowException: mandatory context requires '
      '$requiredTokens tokens, but only $availableTokens are available.';
}
