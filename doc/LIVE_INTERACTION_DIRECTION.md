# Live interaction direction

Omnix is a Cognitive System whose inputs need not originate from a chat screen.
Core is its model-execution component. Hosts may provide microphones, cameras,
sensors, speakers or actuators through explicit adapters.

This is an architectural direction, not a claim of full-duplex audio, continuous
video inference or hard real-time support.

## Ownership

| Owner | Responsibility |
| --- | --- |
| Root Omnix | Interaction identity, coordination, routing and supplied interruption policy |
| Core | Model lifetime, runtime capabilities, resource arbitration and cancellation |
| Knowledge | Explicit indexing, retrieval and provenance |
| Storage | Durable records and checkpoints |
| Workflow | Durable tasks, triggers, progress and recovery |
| Nexus | Authorized peer/device protocol interaction |
| Host | Capture/playback, OS execution, lifecycle, entitlements and UI |

An observation is not authority to act or permission to retain data.
Platform permissions and product policy remain explicit.

## Admission and input contracts

Discrete requests require bounded admission, cancellation and observable busy
or rejected outcomes. See [execution admission](EXECUTION_ADMISSION.md).

Live intake additionally needs source identity, timestamps, payload bounds,
freshness and overflow behavior. Latest-frame replacement can be appropriate
for expendable camera observations, but not automatically for user requests
or durable workflow events.

Slow consumers require backpressure. Cancellation must respect native ownership;
it cannot promise immediate preemption or rollback of accepted external effects.

## Media and physical interaction

Continuous audio needs segmentation or genuine streaming-model input support.
Repeated WAV/image turns do not establish full-duplex interaction or video
understanding. Output audio is a separate capability.

Physical actuation requires host validation and control appropriate to the
device. Safety-critical behavior must not rely on unbounded model response time.

## Assistant applications

Chat bubbles, account access, purchases and capture controls are host concerns.
Applications can adapt their runtime controllers to native events without
defining the engine as a chat-only API.

Independent modules remain usable without root orchestration.
Product entitlement restricts supplied capabilities; it is not generic engine
subscription logic.

Exact context accounting is separate from live intake. Unsupported accounting
must not be replaced by a character-count estimate. See
[context working sets](CONTEXT_WORKING_SET.md).
