# Native integration boundary

Omnix implements model execution and orchestration in Rust.
Dart exposes native APIs; Flutter applications supply presentation and
operating-system adapters.

## Independent modules

Core, Storage, Knowledge, Nexus and Workflow are independently usable Rust
crates. Root Omnix coordinates selected modules and provides sessions and an
optional agent loop. A native module does not require a Dart inference plugin.

Core integrates LiteRT-LM and llama.cpp through their native C interfaces.
Build-time inclusion, runtime selection and model capability checks are separate
concerns. See the [project overview](../README.md).

## Consumer adaptation

Applications adapt their model configuration, stored records and host callbacks
to public Omnix contracts. They do not need to replace unrelated product services
or implement a second agent loop.

Generated bridge types and native handles remain implementation boundaries.
Do not exchange handles between independently loaded module libraries.

## Compatibility and validation

Legacy implementations can inform behavioral tests without remaining runtime
dependencies. Preserve required compatibility identifiers and third-party
license notices when adapting an integration.

Performance comparisons require equivalent models, settings and hardware.
Moving orchestration to Rust does not by itself make model inference faster.

Model execution, native packaging and device interoperability require separate
validation. In particular, a Matter wrapper or a successful build is not proof
of production device-control support.

See [legacy migration](LEGACY_RETIREMENT.md) and
[integration validation](MIGRATION_QUALIFICATION.md).
