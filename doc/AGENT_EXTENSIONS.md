# Registered tools and skills

Root Omnix owns the model/tool/result loop, grants, bounded execution and
cancellation. Core performs inference. Hosts supply executable capabilities.
Skills are instructions, not permission tokens or implementations.

See [extending Omnix](EXTENDING_OMNIX.md) for developer integration versus
user-installed extension packages.

## Rust consumers

Register Core tool definitions and root `ToolExecutor` implementations with
`agent::registry::ToolRegistry`, then supply the registry and grants when
starting an agent. Registration does not silently replace an existing entry.

`SkillCatalog` contains names, descriptions, instructions and required tools.
Its `load_skill` operation exposes selected instructions to the model.
`ToolRegistry::register_skills` can return uniquely associated missing guidance
as `guidance_loaded`, with `actionExecuted: false`, instead of executing a
premature call. A subsequent model call must still satisfy validation and policy.
Ambiguous skill associations require explicit selection.

Custom executors own semantic validation and resource scope. They must
cooperate with cancellation; the engine cannot forcibly stop arbitrary host code.

## Dart consumers

`OmnixHostTool` binds a definition to an asynchronous callback.
`OmnixSkill` supplies instructions and dependencies.
`OmnixAgentExtensions` separates registration, selected skills and grants.

```dart
final session = await engine.startAgent(
  modelPath: modelPath,
  extensions: OmnixAgentExtensions(
    tools: [
      OmnixHostTool(
        name: 'host_time',
        description: 'Read the current UTC time.',
        parameters: {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': <String>[],
          'additionalProperties': false,
        },
        execute: (_) async => {
          'utc': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    ],
    grants: ['host_time'],
  ),
);
try {
  await for (final event in session.sendEvents('What time is it in UTC?')) {
    // Render native events without running another agent loop.
  }
} finally {
  await session.close();
}
```

The registered host-tool schema dialect supports closed objects with scalar
string, boolean, integer or number properties. It is not full JSON Schema.
Unsupported structures and keywords are rejected rather than ignored.
Hosts must validate business rules, filesystem scope and external destinations.

Malformed arguments return recoverable feedback without invoking the host.
Repair consumes the existing execution budget and cannot bypass grants or policy.

## Outcomes and callback lifetime

Tool outcomes distinguish execution status from model prose. A calendar editor
opening is a handoff, not proof that an event was saved.
Applications should render actual outcomes and avoid treating a model's
completion claim as an execution receipt.

The current callback bridge uses per-session correlation IDs, bounded waits
and bounded responses. Cancellation or timeout stops waiting; it does not undo
an already accepted OS action or forcibly terminate host code.
Connect host cancellation to pending permission or approval UI.

The bridge reserves adapter names including `search_knowledge`,
`prepare_email_intent` and `load_skill`. Knowledge needs configured resources;
email proposals do not authorize sending mail. Secrets do not belong in prompts,
skill instructions or ordinary tool results.

## Example-owned capabilities

The Flutter example registers its clock, device and workflow tools in host code.
Its clock skill is at `example/assets/skills/current-time/SKILL.md`.
These are examples, not mandatory engine behavior.

Android host adapters provide bounded operations such as device reads and
editor or application handoffs. OS permissions and application approval policy
are separate checks. The example does not provide unrestricted accessibility
control merely because a tool can open Settings.

## Validation and distribution

Test declared schemas, guidance loading, refusals, callback errors, cancellation
and late results with the actual model and host adapters.
Compiled bridge tests do not replace real-device validation.

Marketplace installation, arbitrary script execution and character profiles
require separate compatibility and trust contracts. Registering a callback is
not a sandbox for downloaded code. No marketplace account is required to use
the engine.

See [agent compatibility](AGENT_PARITY.md) and
[integration validation](MIGRATION_QUALIFICATION.md).
