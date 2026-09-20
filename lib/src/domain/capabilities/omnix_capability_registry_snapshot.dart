// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'omnix_capability.dart';

/// The immutable registration state of one capability.
final class OmnixRegisteredCapability {
  const OmnixRegisteredCapability({
    required this.capability,
    required this.enabled,
  });

  /// The registered capability.
  final OmnixCapability capability;

  /// Whether agents and workflows may currently use the capability.
  final bool enabled;
}

/// An immutable view of a capability registry at one revision.
final class OmnixCapabilityRegistrySnapshot {
  OmnixCapabilityRegistrySnapshot({
    required this.revision,
    required Iterable<OmnixRegisteredCapability> capabilities,
  }) : capabilities = List.unmodifiable(capabilities);

  /// The monotonic revision incremented after every effective mutation.
  final int revision;

  /// The registrations in deterministic insertion order.
  final List<OmnixRegisteredCapability> capabilities;

  /// The enabled skills in deterministic insertion order.
  Iterable<OmnixSkill> get enabledSkills sync* {
    for (final registration in capabilities) {
      if (registration case OmnixRegisteredCapability(
        capability: final OmnixSkill skill,
        enabled: true,
      )) {
        yield skill;
      }
    }
  }

  /// The enabled tools in deterministic insertion order.
  Iterable<OmnixTool> get enabledTools sync* {
    for (final registration in capabilities) {
      if (registration case OmnixRegisteredCapability(
        capability: final OmnixTool tool,
        enabled: true,
      )) {
        yield tool;
      }
    }
  }
}
