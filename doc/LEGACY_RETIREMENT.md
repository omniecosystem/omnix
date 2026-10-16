# Legacy implementation migration

The active implementation uses Rust-owned execution and orchestration, exposed
through the root Dart API and independent module packages. The former
plugin-backed reference application and obsolete root Flutter test driver are
not supported entrypoints.

## Active entrypoints

- Root Flutter integration application: `example/`.
- Independent module implementations and examples: `modules/`.
- Root Rust composition and bridge: `rust/`.
- Root Dart API: `lib/`.

Flutter integration drivers belong to their application package, rather than
the headless root Dart package.

## Updating older integrations

Use the current module READMEs and [project overview](../README.md) to select
features and configure native packaging. Legacy APIs and tests may describe
retired ownership boundaries; restoring them is not a substitute for adapting
a consumer to the current public API.

The native two-agent A2A example no longer invokes the former Dart application
through a subprocess. Host applications provide live callbacks through the
current Nexus integration.

Source-layout changes do not migrate installed application data. Conversation,
workflow and vector-store migrations require their own compatibility checks.
Do not reinterpret an older provider's serialized state as a native checkpoint.

Flutter Edge AI remains a useful external capability reference, not a runtime
dependency of the current native implementation.
