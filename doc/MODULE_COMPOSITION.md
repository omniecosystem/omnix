# Module composition

Use root Omnix when you want selected capabilities coordinated through one API.
Consume module crates directly when you need your own composition.

## One implementation, two entrypoints

```text
Rust host -> root Omnix or independent crates -> Rust implementations
Dart host -> public facade -> native bridge -> Rust implementations
```

Root Dart does not orchestrate companion Dart facades.
The root Rust crate composes selected implementation crates and owns its handles.
Independent Dart module packages expose alternative entrypoints.

## Rust feature selection

Root Omnix has no default modules or Flutter bridge.
Select a Core runtime explicitly, such as `core-litertlm` or `core-llamacpp`.
Selecting the Core contract does not select an engine implicitly.

Other features select Knowledge, Workflow, Storage and Nexus integrations.
Compatibility aliases exist; consult `rust/Cargo.toml` for the complete set.
Cargo features are additive across a dependency graph.

```toml
[dependencies]
omnix = { path = "/path/to/omnix/rust", default-features = false, features = ["core-litertlm"] }
```

Independent Rust modules do not depend on Dart or Flutter.
Adding a module does not mean every backend or protocol must be included.

## Dart and native packaging

Dart has no Cargo-style optional pub dependencies. Native components are selected
through build-hook configuration; omitting an import alone does not establish
native-library exclusion.

The root Dart API is headless. Current Core, Storage, Knowledge and Nexus package
build integration requires the Flutter SDK. Workflow is an independent Rust
crate and is exposed through root Dart, without a standalone Dart package.

Source-built artifacts require Rust and native target compiler tools.
Precompiled public distribution is a separate delivery concern.

## Ownership

Do not transfer native handles between libraries or independently opened bridges.
Each registry belongs to its creating implementation instance.

Compatible build-time asset ownership can prevent duplicate runtime filenames,
but does not merge model pools or handle registries.
Selected module composition must preserve one owner for each live resource.

## Host integration

The Flutter example separates Core, Storage, Knowledge, Nexus and Workflow
configuration from the shared Home interaction.
UI features do not require independent agents or model instances.

Hosts own accounts, entitlements, capture, OS permissions and background
wakeups. Native execution and orchestration remain in Rust.

See the [project overview](../README.md) and
[example architecture](EXAMPLE_ARCHITECTURE.md).
