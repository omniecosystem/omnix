# Extending Omnix

Omnix is a modular Cognitive System. Developers embed and configure it within
applications, services or devices. Core supplies model execution; root Omnix
coordinates selected capabilities. OmniAsk is one consumer, not a prerequisite.

## Extension boundaries

| Participant | Responsibility |
| --- | --- |
| Engine contributor | Reusable native behavior and public contracts |
| Application developer | Host tools, platform adapters, UI and product policy |
| Extension author | Compatible instructions/configuration or an explicitly supported implementation |
| End user | Installation and configuration through an application's interface |

Developer registration and end-user package installation are distinct.
Instructions do not implicitly grant permissions, and a catalog listing does
not establish executable-code trust.

## Developer API

Use the public root API to supply `OmnixAgentExtensions` with tool definitions,
callbacks, skill instructions, selected skills and grants.
See [tools and skills](AGENT_EXTENSIONS.md).

This configuration extends Omnix's optional agent capability. It is not a
universal plugin container for runtime backends, storage engines or character
packages. Developers need public lifecycle and execution contracts, not
generated bridge internals.

Rust retains orchestration and policy enforcement. Dart callbacks implement
host actions rather than a competing model/tool loop. Rust consumers can use
the public registry and executor contracts directly.

## Tools, skills and profiles

Tools implement callable operations. Skills explain how to combine available
operations. Neither registration nor an instruction body grants authority.

Character/profile packages are a development direction for selecting model
configuration and skills. A general package installer and executable-extension
sandbox are separate capabilities, not consequences of callback support.

Omnies can distribute compatible packages without becoming a required runtime
dependency. Applications remain responsible for compatibility, integrity,
capability grants, updates and revocation.

## Host obligations

- Validate model arguments and domain semantics before side effects.
- Apply OS permissions and the application's supplied execution policy.
- Report real outcomes rather than inferred success.
- Connect cancellation and lifecycle changes to pending operations.
- Keep credentials outside ordinary prompts and tool results.
- Treat host callbacks as trusted application code, not a sandbox.

Cancellation cannot roll back an OS action already accepted.

## Device automation

A developer can supply native accessibility, notification, capture or device
services through host adapters where the platform permits them.
Omnix does not bypass platform restrictions or guarantee identical OS services
on every target.

Workflow provides durable execution primitives; the host supplies wakeups and
executors. This is distinct from an always-running OS service.
Knowledge supplies retrieval, Storage persists state, and Nexus supplies
protocol/device connectivity. Root Omnix coordinates these selected modules.

See the [example architecture](EXAMPLE_ARCHITECTURE.md) for a host integration.
