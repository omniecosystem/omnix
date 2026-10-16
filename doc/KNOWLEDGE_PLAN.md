# Knowledge and Workflow integration

Knowledge and Workflow serve different lifecycles. Knowledge makes indexed
information available for retrieval; Workflow tracks durable execution.
Neither replaces the interactive agent loop in root Omnix.

## Ownership

| Component | Responsibility |
| --- | --- |
| Core | Model execution, embeddings, model sessions and inference-resource arbitration |
| Storage | Structured persistence, snapshots, checkpoints and vector indexes |
| Knowledge | Content identity, provenance, indexing, retrieval and embedding compatibility |
| Workflow | Durable execution state, attempts, cancellation and recovery |
| Nexus | Peer identity, authorization, communication and device access |
| Root Omnix | Agent loop, tool dispatch, bounded iterations and cross-module coordination |
| Host | Presentation, accounts, media capture, permissions and OS background services |

## Knowledge integration

Supply an embedding provider and a compatible storage adapter explicitly.
Vector retrieval does not require a generation model. Core executes embeddings;
Storage persists vectors; Knowledge coordinates indexing and retrieval.

Preserve document identity and source metadata independently of a vector
backend's internal identifiers. Embedding compatibility depends on the model
and preprocessing profile, not just vector dimensions. Changing a profile may
require rebuilding the index rather than reopening it under a new encoder.

Applications supply extracted content and associated metadata. File pickers,
document-format decoding and product-specific upload interfaces are host
integrations, not prerequisites for using native retrieval.

For a complete integration example, see the
[Knowledge module](../modules/omnix_knowledge/README.md).

## Workflow integration

Workflow persists execution progress and results. A host provides executors
and wakeups appropriate to its platform. An executor may invoke a tool or
agent interaction, but an interactive conversation does not require a durable
Workflow job.

Core inference-resource arbitration is separate from Workflow scheduling:
one controls access to a runtime, while the other tracks when durable work
is eligible to execute.

See the [Workflow module](../modules/omnix_workflow/README.md) for checkpoint
and recovery behavior.

## Agent integration

Root Omnix coordinates model requests and registered tools. Developers supply
skill instructions, tool definitions, callbacks and policies. Knowledge
retrieval can be exposed as an available capability; Workflow can preserve
multi-step work beyond the current interaction.

Instructions describe intended behavior, not evidence that an action ran.
Execution results and durable checkpoints establish what actually completed.

## Validation

Test indexing, close/reopen, attributed retrieval and generation separately.
For durable execution, test cancellation and recovery after interruption,
including actions that cannot safely be repeated.

Mock-provider tests verify contracts; they do not establish native model
quality, persistent-backend behavior or packaged application compatibility.
Exact token accounting and modality support depend on the selected runtime.
