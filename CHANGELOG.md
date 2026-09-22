## Unreleased

- Add provider-neutral Knowledge documents, chunks, access labels, sources,
  citations, embedding-space identities, and local or transport-ready semantic
  query contracts.
- Add a Knowledge coordinator for validated indexing, durable flushes,
  deterministic access-filtered retrieval, semantic-space compatibility, and
  token-budgeted RAG context assembly.
- Add a strict versioned codec for transporting semantic queries and attributed
  retrieval matches across future node boundaries.

## 0.1.0-dev.2

- Add provider-neutral context budgets, token-estimator contracts, and a recent
  history policy that preserves mandatory system information.
- Allow conversations and agents to replay context-policy-selected history when
  a session opens.
- Add durable conversation snapshot and repository contracts plus a strict,
  versioned JSON codec with multimodal message support.
- Add a durable conversation coordinator that restores bounded active context,
  serializes context restoration with inference, and atomically stores complete
  successful turns without deleting trimmed history.
- Serialize native conversation and agent-session creation, history replay, and
  standalone history replacement through the shared inference scheduler.
- Allow hosts to supply an application-owned inference scheduler and retain its
  lifecycle ownership.
- Allow augmented model input to retain a separate durable user-visible prompt.

## 0.1.0-dev.1

- Establish the Omnix Flutter and Rust package foundation.
- Add a headless engine lifecycle contract and native bridge handshake.
- Add a framework-neutral, non-preemptive inference scheduler with priority,
  FIFO, streaming, lifecycle, and immutable state snapshot guarantees.
- Add portable model-manifest contracts and strict validation for the Omnies
  registry and pinned public LiteRT-LM downloads.
- Add the first thin inference boundary: a plugin-independent conversation API
  and a Flutter Gemma adapter for streamed text, thinking, and tool calls.
- Add an application runtime that owns engine initialization and deterministic
  conversation cleanup.
- Add neutral model-source, installation, progress, cancellation, storage, and
  integrity contracts with a LiteRT-LM-backed Flutter Gemma implementation.
- Add a one-call `FlutterGemmaOmnix.createRuntime()` composition and a runnable
  model-installation and streaming-conversation example.
- Add provider-neutral skill and tool contracts, a runtime-owned shared
  capability registry, observable enablement state, host permission policy,
  and structured tool execution outcomes.
- Validate tool arguments against a documented JSON Schema subset before
  permission evaluation and execution.
- Add a Flutter Gemma Agent skill-catalog adapter that makes Omnix enablement
  authoritative while preserving provider execution metadata.
- Add provider-neutral agent sessions, orchestration events, structured tool
  outputs, runtime lifecycle ownership, and a Flutter Gemma Agent backend.
- Add a typed, temporary native-chat bridge to support incremental migration of
  existing history and voice integrations.
- Document the provider-neutral audio and speech boundary without making a
  dedicated speech-model package mandatory.
- Define capability-oriented module boundaries for Core, Workflow, Knowledge,
  Nexus, skills, and tools without prematurely splitting packages.
- Add a durable Workflow runtime with atomic task/event transitions, executor
  ports, retries, cooperative cancellation, restart recovery, and shared
  inference-scheduler arbitration.
- Make `OmnixRuntime` own one scheduler for conversation and agent turns, expose
  it to workflows, and drain active inference safely during shutdown.
- Add a strict, versioned JSON-compatible Workflow codec for portable durable
  storage adapters.
- Add architecture, contribution, security, and CI foundations.
