# Example architecture

The Flutter example consumes Omnix; it is not a second implementation of its
execution or orchestration. Features follow module responsibilities, with
Home as the shared interaction surface.

## Layout

```text
example/lib/
  app/                         Application shell and composition
  features/
    home/                      Conversation UI and host adapters
    core/                      Model configuration, import and transfer UI
    knowledge/                 Indexing and retrieval UI
    nexus/                     Connectivity and device UI
    storage/                   Persistence demonstrations
    workflow/                  Durable-task UI and background host integration
  shared/                      Cross-feature host utilities
```

Substantial features use presentation and data layers. Additional domain
abstractions are useful only when they isolate real host logic; an extra Dart
use case is unnecessary merely to rename a Rust API call.

## Native composition

```text
Home UI -> root Dart session API -> root Rust bridge -> selected Rust modules
```

Root Rust owns sessions, agent orchestration and model leases. Dart wraps the
bridge and manages asynchronous client state. Standalone module APIs remain
independent entrypoints, not a second orchestration path for Home.

Core owns inference resources, Knowledge owns retrieval coordination, Workflow
owns durable execution, Storage owns persistence, and Nexus owns connectivity.
Feature screens provide configuration and focused demonstrations; they are not
independent agents.

## Host responsibilities

Controllers manage presentation state. Host services provide file selection,
microphone capture, permission interaction and OS-managed background work.
Repositories adapt SDK results and application-local persistence.

Developers supply tools, skills and policies. Rust enforces the supplied
execution policy; the host implements the actions and any approval UI.

Native handles belong to the bridge instance that created them. Do not transfer
handles between module libraries or concurrently open one vector-store location
through independent owners.

## Testing

Keep feature tests aligned with their ownership. UI tests with doubles do not
establish native model or platform behavior. Native integration tests require
matching libraries, selected runtime features and compatible models.

Use canonical directory names in imports and editor workspaces. Windows
short-path aliases refer to the same underlying directories, not duplicate
modules.

See the [project overview](../README.md) and
[module responsibilities](MODULES.md) for API and packaging boundaries.
