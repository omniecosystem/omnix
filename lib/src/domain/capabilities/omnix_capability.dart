// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// The execution role a capability plays inside an intelligence runtime.
enum OmnixCapabilityKind {
  /// Reusable instructions that teach an agent how to accomplish a goal.
  skill,

  /// An atomic operation backed by executable host or platform behavior.
  tool,
}

/// A host-defined permission required by a capability.
final class OmnixCapabilityPermission {
  /// Creates a permission with a stable, non-empty [id].
  OmnixCapabilityPermission(String id) : id = _requireText(id, 'id');

  /// The stable permission identifier.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is OmnixCapabilityPermission && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// Provider-neutral identity and presentation metadata for a capability.
final class OmnixCapabilityMetadata {
  /// Creates validated metadata for a skill or tool.
  OmnixCapabilityMetadata({
    required String id,
    required this.kind,
    required String name,
    required String description,
    String version = '1.0.0',
    Set<OmnixCapabilityPermission> requiredPermissions = const {},
  }) : id = _requireText(id, 'id'),
       name = _requireText(name, 'name'),
       description = _requireText(description, 'description'),
       version = _requireText(version, 'version'),
       requiredPermissions = Set.unmodifiable(requiredPermissions);

  /// The stable identifier used by registries and persisted preferences.
  final String id;

  /// The capability role.
  final OmnixCapabilityKind kind;

  /// The human-readable name supplied by the capability author.
  final String name;

  /// The human-readable description supplied by the capability author.
  final String description;

  /// The author-defined capability version.
  final String version;

  /// The permissions that must be approved before execution or disclosure.
  final Set<OmnixCapabilityPermission> requiredPermissions;
}

/// A capability that can be registered with an Omnix runtime.
sealed class OmnixCapability {
  const OmnixCapability(this.metadata);

  /// The capability's stable metadata.
  final OmnixCapabilityMetadata metadata;
}

/// Reusable agent instructions with optional dependencies on registered tools.
final class OmnixSkill extends OmnixCapability {
  /// Creates an instructional capability.
  OmnixSkill({
    required OmnixCapabilityMetadata metadata,
    required String instructions,
    Set<String> toolIds = const {},
  }) : instructions = _requireText(instructions, 'instructions'),
       toolIds = Set.unmodifiable(
         toolIds.map((id) => _requireText(id, 'toolId')),
       ),
       super(_requireKind(metadata, OmnixCapabilityKind.skill));

  /// The instructions disclosed to an agent when the skill is loaded.
  final String instructions;

  /// The registered tool identifiers this skill may ask an agent to use.
  final Set<String> toolIds;
}

/// An atomic executable capability exposed to agents and workflows.
final class OmnixTool extends OmnixCapability {
  /// Creates a tool backed by [execute].
  OmnixTool({
    required OmnixCapabilityMetadata metadata,
    required this.execute,
    Map<String, Object?> inputSchema = const {},
  }) : inputSchema = Map.unmodifiable(inputSchema),
       super(_requireKind(metadata, OmnixCapabilityKind.tool));

  /// The JSON Schema-like input contract advertised to callers.
  final Map<String, Object?> inputSchema;

  /// The host or platform implementation of the operation.
  final OmnixToolExecutor execute;
}

/// Executes a tool invocation and returns a structured outcome.
typedef OmnixToolExecutor =
    FutureOr<OmnixToolResult> Function(OmnixToolInvocation invocation);

/// One request to execute a registered tool.
final class OmnixToolInvocation {
  /// Creates an immutable invocation.
  OmnixToolInvocation({
    required String toolId,
    required String callId,
    Map<String, Object?> arguments = const {},
  }) : toolId = _requireText(toolId, 'toolId'),
       callId = _requireText(callId, 'callId'),
       arguments = Map.unmodifiable(arguments);

  /// The requested tool identifier.
  final String toolId;

  /// The caller-provided identifier used to correlate the result.
  final String callId;

  /// The immutable arguments supplied to the tool.
  final Map<String, Object?> arguments;
}

/// The structured outcome of a tool invocation.
sealed class OmnixToolResult {
  const OmnixToolResult();
}

/// A successfully completed tool invocation.
final class OmnixToolSuccess extends OmnixToolResult {
  const OmnixToolSuccess(this.value);

  /// The tool-defined result value.
  final Object? value;
}

/// A category describing why a tool invocation could not complete.
enum OmnixToolFailureCode {
  /// No tool is registered under the requested identifier.
  notFound,

  /// The tool is registered but currently disabled.
  disabled,

  /// The active permission policy rejected the invocation.
  permissionDenied,

  /// The tool implementation reported an invalid request.
  invalidArguments,

  /// The tool implementation failed while executing.
  executionFailed,
}

/// A tool invocation that ended without a successful value.
final class OmnixToolFailure extends OmnixToolResult {
  const OmnixToolFailure({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  /// The machine-readable failure category.
  final OmnixToolFailureCode code;

  /// The diagnostic message suitable for logs or agent context.
  final String message;

  /// Whether retrying later may succeed without changing the invocation.
  final bool retryable;
}

OmnixCapabilityMetadata _requireKind(
  OmnixCapabilityMetadata metadata,
  OmnixCapabilityKind expected,
) {
  if (metadata.kind != expected) {
    throw ArgumentError.value(
      metadata.kind,
      'metadata.kind',
      'Expected ${expected.name}.',
    );
  }
  return metadata;
}

String _requireText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}
