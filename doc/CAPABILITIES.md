# Skills and tools

Omnix represents reusable agent behavior through two capability kinds:

- A **skill** is an instructional bundle that explains how to accomplish a
  goal and may reference tools.
- A **tool** is one atomic executable operation with a declared input schema.

This distinction keeps prompts and procedural knowledge separate from trusted
host or platform code. Skills cannot bypass tool enablement or permission
policy merely by referencing a tool.

## Shared registry

Every `OmnixRuntime` owns one `OmnixCapabilityRegistry`. Interactive agents and
workflow tasks are expected to consume this same registry so enablement and
permission decisions remain consistent across execution modes.

Registrations have stable identifiers and deterministic insertion order. The
registry publishes immutable snapshots whenever a capability is registered,
removed, enabled, or disabled. A host can persist selected identifiers and
render its own interface without introducing UI dependencies into Omnix.

## Permission boundary

Capabilities declare host-defined permission identifiers. The default policy
allows capabilities that require no permissions and denies restricted ones.
Applications opt into platform access by supplying an
`OmnixCapabilityPermissionPolicy` that evaluates those identifiers through
their own consent and permission systems.

Permission checks occur immediately before tool execution. A skill being
enabled does not implicitly grant permission to any tool it references.

## Tool outcomes

Tool invocations carry a correlation identifier and immutable arguments.
Execution returns either `OmnixToolSuccess` or `OmnixToolFailure`. Registry
failures such as missing tools, disabled tools, denied permissions, and
executor exceptions therefore remain structured instead of being exposed as
provider-specific errors.

Input schemas are currently descriptive. Schema validation and agent-provider
adaptation belong to the next capability milestone.
