# Execution responsibilities

Omnix separates native execution, cross-module coordination and host services.

| Responsibility | Owner |
| --- | --- |
| Runtime loading, native lifetime and capabilities | Core |
| Model execution and runtime resource arbitration | Core |
| Interaction sessions and cross-module coordination | Root Omnix |
| Agent tool/result loop and supplied-policy enforcement | Root Omnix |
| Indexing and retrieval orchestration | Knowledge |
| Durable records and vector persistence | Storage |
| Durable task execution and recovery | Workflow |
| Peer/device protocol access | Nexus |
| Capture, playback, OS permissions and product interface | Host |

Dart exposes Rust behavior. Client-side asynchronous state does not require
a second inference scheduler or agent implementation.

## Discrete work and live observations

A sensor event is not automatically a conversation turn.
A host may submit observations with source identity, capture time, payload
limits and an explicit purpose. Continuous input additionally needs freshness,
overflow and backpressure contracts.

Expendable camera previews can use latest-frame replacement; user requests and
durable events must not silently disappear under the same policy.
Audio buffering must preserve the intended signal rather than indiscriminately
drop segments.

## Resource and safety boundaries

Queue capacity, deadlines, cancellation and resource ownership need observable
outcomes. A serialized runtime worker is not by itself a complete cross-module
scheduling policy.

Battery, thermal state, memory pressure, background restrictions and disconnected
devices affect host integrations. Native cancellation is cooperative, not a
guarantee of instantaneous preemption.

Safety-critical physical control must not depend on an LLM's probabilistic
latency or output.

## Current integration and future direction

The native implementation includes sessions, agents, shared model leases and
execution-admission controls. These discrete-request mechanisms do not establish
continuous sensor ingestion, full-duplex audio, video inference or hard real-time
control.

See [execution admission](EXECUTION_ADMISSION.md),
[live interaction direction](LIVE_INTERACTION_DIRECTION.md), and the
[project overview](../README.md) for current boundaries.
