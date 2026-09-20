// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_gemma_agent/flutter_gemma_agent.dart' as agent;

import '../../application/capabilities/omnix_capability_registry.dart';
import '../../domain/capabilities/omnix_capability.dart';
import '../../domain/capabilities/omnix_capability_registry_snapshot.dart';

/// Resolves host permissions required by one Flutter Gemma Agent skill.
typedef FlutterGemmaAgentPermissionResolver =
    Set<OmnixCapabilityPermission> Function(agent.Skill skill);

/// Bridges a Flutter Gemma Agent skill catalog into Omnix capabilities.
final class FlutterGemmaAgentSkillAdapter {
  /// Creates an adapter over [skills].
  ///
  /// Duplicate skill names are rejected because Omnix registration identifiers
  /// must be unambiguous. [permissionResolver] lets the host attach its own
  /// consent policy without exposing platform permission types to Omnix.
  FlutterGemmaAgentSkillAdapter(
    Iterable<agent.Skill> skills, {
    FlutterGemmaAgentPermissionResolver? permissionResolver,
  }) : _permissionResolver = permissionResolver ?? _noPermissions {
    for (final skill in skills) {
      if (_sourceSkills.containsKey(skill.name)) {
        throw ArgumentError.value(
          skill.name,
          'skills',
          'Duplicate Flutter Gemma Agent skill name.',
        );
      }
      _sourceSkills[skill.name] = skill;
    }
  }

  final FlutterGemmaAgentPermissionResolver _permissionResolver;
  final Map<String, agent.Skill> _sourceSkills = {};

  /// The imported neutral skills in source insertion order.
  Iterable<OmnixSkill> get skills sync* {
    for (final skill in _sourceSkills.values) {
      yield _toOmnix(skill);
    }
  }

  /// Registers every imported skill into [registry].
  ///
  /// Identifiers in [enabledSkillIds] begin enabled; all others remain
  /// available but disabled.
  void registerWith(
    OmnixCapabilityRegistry registry, {
    Set<String> enabledSkillIds = const {},
  }) {
    for (final skill in skills) {
      registry.register(
        skill,
        enabled: enabledSkillIds.contains(skill.metadata.id),
      );
    }
  }

  /// Builds the provider registry represented by [snapshot].
  ///
  /// Only skills imported by this adapter are included. Omnix metadata and
  /// instructions remain authoritative, while provider execution metadata is
  /// retained from the corresponding source skill.
  agent.SkillRegistry buildProviderRegistry(
    OmnixCapabilityRegistrySnapshot snapshot,
  ) {
    final providerRegistry = agent.SkillRegistry();
    for (final registration in snapshot.capabilities) {
      final capability = registration.capability;
      if (capability is! OmnixSkill) continue;
      final source = _sourceSkills[capability.metadata.id];
      if (source == null) continue;
      providerRegistry.add(
        agent.Skill(
          name: capability.metadata.id,
          description: capability.metadata.description,
          instructions: capability.instructions,
          type: source.type,
          metadata: source.metadata,
          scriptName: source.scriptName,
        ),
        selected: registration.enabled,
      );
    }
    return providerRegistry;
  }

  OmnixSkill _toOmnix(agent.Skill skill) => OmnixSkill(
    metadata: OmnixCapabilityMetadata(
      id: skill.name,
      kind: OmnixCapabilityKind.skill,
      name: skill.name,
      description: skill.description,
      requiredPermissions: _permissionResolver(skill),
    ),
    instructions: skill.instructions,
    toolIds: switch (skill.type) {
      agent.SkillType.textOnly => const {},
      agent.SkillType.js => const {agent.AgentToolNames.runSkill},
      agent.SkillType.intent => const {agent.AgentToolNames.runIntent},
      agent.SkillType.mcp => const {agent.AgentToolNames.runMcp},
    },
  );

  static Set<OmnixCapabilityPermission> _noPermissions(agent.Skill _) =>
      const {};
}
