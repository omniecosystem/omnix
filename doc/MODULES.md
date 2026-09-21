# Omnix modules

Omnix is modular by reusable engine capability, not by application screen.
Host features can align with these modules without forcing every piece of
product UI into the engine.

## Initial boundaries

- **Core and inference**: runtime lifecycle, model lifecycle, conversations,
  provider-neutral agent sessions and events, context policy, and inference
  scheduling.
- **Skills and tools**: capability metadata, a runtime-owned shared registry,
  enablement snapshots, host permission policy, and structured tool execution
  are available. Flutter Gemma Agent catalog and session adapters are
  available; portable package loading remains in progress.
- **Workflow**: durable task and event contracts, atomic persistence boundary,
  scheduling policy, retries, cooperative cancellation, and restart recovery
  are available; production storage adapters remain host-selected.
- **Knowledge**: documents, embeddings, retrieval, and access-policy contracts.
- **Nexus**: discovery and control contracts for devices and local services.

The host owns the corresponding presentation, navigation, localization,
account, entitlement, and interaction design. Features that exist only to
serve those product concerns do not require an Omnix module.

## Packaging rule

These boundaries begin as directories and public API surfaces inside the single
`omnix` package. A module becomes a separate package only when it has an
independent release cycle, platform dependency, or meaningful reuse outside the
main runtime. This keeps the architecture explicit without creating dependency
and versioning overhead prematurely.

Cross-cutting contracts live at the lowest sensible boundary. For example,
skills are not owned by Workflow because both interactive agents and workflow
tasks consume them.
