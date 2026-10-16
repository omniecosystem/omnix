# Module integration coverage

Omnix's modules divide responsibilities rather than mirror an upstream
package catalog. Public API similarity is not proof of behavioral compatibility.

| Module | Integration surface | Validation focus |
| --- | --- | --- |
| Core | LiteRT-LM/llama.cpp selection, conversations and embeddings | Model compatibility, streaming, cancellation, context and native lifetime |
| Storage | SQLite records/checkpoints and Qdrant vectors | Atomic writes, profile compatibility, reopen and ownership |
| Knowledge | Attributed indexing and retrieval | Stable source IDs, visibility, profile checks and durable updates |
| Workflow | Durable sequential execution and recovery | Saved results, retry safety, reconciliation and cancellation |
| Nexus | A2A and experimental Matter adapters | Authentication, grants, callback ownership and device interoperability |
| Root Omnix | Sessions and agent coordination | Shared resources, structured outcomes and cross-module ownership |

## Independent selection

Backend and protocol components are opt-in.
Importing an API cannot add a native component omitted from the build.
Unsupported operations must remain distinguishable from invalid configuration
or execution failure.

## Capability distinctions

SQLite conversation storage is not SQLite vector search.
Vector storage is not a complete retrieval pipeline.
An embedding model is not a generation model.
A2A networking is not the agent loop.
A checkpoint is not proof that an external side effect completed.

## Behavioral checks

Test normal operation, failure, cancellation and restart independently.
Use real native adapters where packaging or persistence is the subject of a test.
Mock providers establish contracts, not model quality or device interoperability.

Target coverage differs by module and backend.
See the [project overview](../README.md),
[Core compatibility](CORE_PARITY.md), and
[Matter backend boundaries](MATTER_BACKENDS.md).
