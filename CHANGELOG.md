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
- Define capability-oriented module boundaries for Core, Workflow, Knowledge,
  Nexus, skills, and tools without prematurely splitting packages.
- Add architecture, contribution, security, and CI foundations.
