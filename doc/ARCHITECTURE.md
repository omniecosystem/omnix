# Omnix architecture

## Product boundary

Omnix owns reusable intelligence behavior. A host application owns
presentation, navigation, localization, account integration, entitlement,
branding, and product policy.

Omnix must not expose Flutter widgets, `BuildContext`, Supabase types, purchase
SDK types, `flutter_gemma` session objects, or generated Rust bridge types.

Module boundaries follow reusable engine capabilities rather than application
screens. See [Omnix modules](MODULES.md) for the initial boundaries and the rule
for splitting them into packages.

## Dependency direction

```text
Host application
      |
      v
Public Omnix API
      |
      v
Application orchestration
      |
      v
Domain contracts <--- Infrastructure adapters
                           |       |
                           |       +--- Dart and platform plugins
                           +----------- Rust through generated bindings
```

Domain code has no dependency on infrastructure. Infrastructure implements
domain contracts. The application layer is the composition boundary.

While the Flutter Gemma ecosystem remains part of the stack, it belongs behind
Omnix infrastructure adapters:

```text
Host application -> Omnix public API -> Flutter Gemma adapter
                 -> flutter_gemma -> LiteRT-LM
```

The host selects product behavior and renders it. Omnix owns model and session
lifecycle, inference scheduling, conversations, agents, skills, tools,
workflows, and knowledge contracts. Plugin-specific objects never cross the
public Omnix boundary, allowing an adapter or native implementation to be
replaced without rewriting the host.

## Migration rule

Moving proven behavior from an existing host into Omnix follows this sequence:

1. Characterize existing behavior with tests.
2. Define an implementation-independent Omnix contract.
3. Copy the existing implementation with minimal edits.
4. Make the host consume Omnix through its public API.
5. Verify behavioral parity on supported platforms.
6. Introduce a Rust implementation behind the same contract.
7. Remove the old implementation only after parity is demonstrated.

Large source files are copied before refactoring so extraction and behavioral
changes remain separate, reviewable commits.

## Initial module order

1. Runtime events and inference scheduling contracts. (Available: the runtime
   owns one non-preemptive queue shared by conversation and agent turns and
   exposed to Workflow executors.)
2. Model identity, installation, and verification contracts. (In progress:
   portable marketplace-manifest validation, LiteRT-LM initialization,
   installation, cancellation, storage operations, and native artifact
   verification are available behind plugin-independent contracts.)
3. Skill and tool registry contracts. (In progress: provider-neutral skills,
   tools, enablement, permission policy, runtime ownership, and structured tool
   execution are available; provider adapters and package loading remain.)
4. Workflow task state and coordination contracts. (Foundation available:
   durable transitions and event history, retries, cooperative cancellation,
   restart recovery, executor ports, and shared scheduler arbitration.)
5. Conversation and agent session coordination. (In progress: provider-neutral
   conversation and agent contracts, Flutter Gemma adapters, shared scheduling,
   and deterministic shutdown are available; more host orchestration remains
   to migrate.)
6. Knowledge and retrieval contracts.
7. Persistent stores and platform adapters.

The first Rust migrations should be bounded operations such as hashing,
manifest validation, safe package extraction, graph validation, and context
budgeting. Inference-session ownership remains in Dart while the active model
runtime is provided by Flutter plugins.

## Compatibility

The Dart package follows semantic versioning. Native bridge compatibility has
an independent integer API version. Persisted event and manifest formats must
carry explicit schema versions.
