// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/context/omnix_context.dart';
import '../../domain/inference/omnix_message.dart';

/// A conservative estimator suitable when a provider tokenizer is unavailable.
///
/// Text is approximated at four Unicode code points per token. Providers that
/// expose exact tokenization should supply their own [OmnixTokenEstimator].
final class OmnixApproximateTokenEstimator implements OmnixTokenEstimator {
  const OmnixApproximateTokenEstimator({
    this.messageOverheadTokens = 4,
    this.imageTokens = 256,
    this.audioTokens = 512,
  });

  final int messageOverheadTokens;
  final int imageTokens;
  final int audioTokens;

  @override
  int estimateText(String text) => (text.runes.length / 4).ceil();

  @override
  int estimateMessage(OmnixMessage message) {
    var estimate = messageOverheadTokens + estimateText(message.text);
    if (message.imageBytes != null) estimate += imageTokens;
    estimate += message.images.length * imageTokens;
    if (message.audioBytes != null) estimate += audioTokens;
    return estimate;
  }
}

/// Keeps mandatory system information and the newest contiguous history that
/// fits within a context budget.
final class OmnixRecentContextPolicy implements OmnixContextPolicy {
  const OmnixRecentContextPolicy({
    required this.budget,
    this.estimator = const OmnixApproximateTokenEstimator(),
    this.preserveSystemInformation = true,
  });

  final OmnixContextBudget budget;
  final OmnixTokenEstimator estimator;
  final bool preserveSystemInformation;

  @override
  OmnixContextSelection select(
    List<OmnixMessage> history, {
    List<OmnixMessage> additionalMessages = const [],
  }) {
    final available = budget.availableInputTokens;
    final indexed = history.indexed.toList(growable: false);
    final mandatory = <(int, OmnixMessage)>[];
    var used = 0;

    for (final message in additionalMessages) {
      used += estimator.estimateMessage(message);
    }
    if (preserveSystemInformation) {
      for (final entry in indexed) {
        if (entry.$2.kind == OmnixMessageKind.systemInfo) {
          mandatory.add(entry);
          used += estimator.estimateMessage(entry.$2);
        }
      }
    }
    if (used > available) {
      throw OmnixContextOverflowException(
        requiredTokens: used,
        availableTokens: available,
      );
    }

    final selectedIndexes = mandatory.map((entry) => entry.$1).toSet();
    for (final entry in indexed.reversed) {
      if (selectedIndexes.contains(entry.$1)) continue;
      final cost = estimator.estimateMessage(entry.$2);
      if (used + cost > available) break;
      selectedIndexes.add(entry.$1);
      used += cost;
    }

    final selected = indexed
        .where((entry) => selectedIndexes.contains(entry.$1))
        .map((entry) => entry.$2)
        .toList(growable: false);
    return OmnixContextSelection(
      messages: selected,
      estimatedInputTokens: used,
      omittedMessageCount: history.length - selected.length,
    );
  }
}
