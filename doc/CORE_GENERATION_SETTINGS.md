# Native generation controls

The root Omnix API and standalone Core API accept optional sampler settings:
temperature (0–2), top-K (1–10000), top-P (greater than 0, at most 1), and
seed (0–2147483647). Omission preserves existing native defaults; temperature
zero explicitly selects greedy decoding. Equal settings do not promise equal
outputs across runtimes, hardware, or runtime versions.

Rust validates the settings and configures the native C API directly. LiteRT-LM
uses session sampler parameters, while llama.cpp uses an owned sampler chain.
Dart transports carry configuration only; they do not sample tokens themselves.

The example's Core screen exposes context size and custom sampling. Settings
apply to both ordinary and registered-agent Home sessions. Saved chats retain
their context size, output budget and sampler. Older chats use context 4096 and
native-default sampling. Agent checkpoints reject mismatched sampling rather
than silently changing a reopened conversation. Custom transports must support
the sampling interface or explicitly reject requests.

## Live updates

- Live response-budget and sampler changes are now implemented through Rust,
  Dart, and the example's "Update this conversation" panel. Edits are staged
  until Apply. Busy sessions and pending tool results reject changes. Native
  context is retained without invoking host executors. Context size and system
  instructions still require a new chat. Reopened chats prepare and restore
  native context before exposing live changes; no additional user turn is needed.
- Successful live changes update saved metadata and agent checkpoints. A failed
  save attempts to restore previous native settings; failed rollback releases
  the live handle instead of continuing with untracked configuration.

Windows CPU qualification with the existing Gemma 4 E2B model passed: a completed
fact-bearing turn survived a budget/sampler update, recall succeeded afterward,
and a rejected invalid update did not invalidate the chat. This is native Rust
evidence, not an Android or packaged Flutter qualification result. Tool-history
validation and executor-free agent updates are covered separately by unit tests.

## Explicit reasoning output

Rust `ConversationOptions.thinking` and Dart `thinking: true` configure the
official LiteRT-LM thinking setter. Omission keeps thinking disabled. This is a
conversation setting, not an instruction pretending to constrain generation.
Unsupported transports and the current llama.cpp reasoning-channel adapter
reject the request; no channel is guessed from prose or `<think>` tags.

Core's typed stream carries `ConversationDelta::Text/Reasoning`; standalone
Dart exposes `sendMessageEvents` with `OmnixCoreOutput`, and root Dart exposes
`OmnixOutputDelta` and agent reasoning events. Existing text-only methods retain
their visible-text behavior. Root Rust carries reasoning through both the first
model turn and continuations after tool results. Complete tool calls remain
validated and authorized before host execution. Reasoning is not tool authority.

Native checkpoints preserve canonical assistant `reasoning_content` separately
from visible content. Old checkpoints without the new thinking setting mean
`false`; incompatible settings and malformed reasoning metadata fail explicitly.
Checkpoint operations never dispatch saved tools. A reasoning-bearing ordinary
history uses the opaque native checkpoint envelope instead of lossy text export.
Strict restoration still rejects a thinking mismatch. Callers can instead
explicitly supply the desired future thinking flag when restoring. Rust checks
the saved flag and all other checkpoint invariants before changing only future
generation behavior; Dart does not edit opaque checkpoints or discard history.

Live `setThinking` updates are available through root and standalone Core APIs.
LiteRT-LM retains model weights and owned history, releases only the current
conversation, and replays that history when the next native turn begins. This
is not a saved KV-tensor snapshot and does not execute historical tools. Busy
sessions and unresolved tool results reject changes. OmniAsk persists the
updated checkpoint and rolls back the flag on a failed save; failed rollback
closes the uncertain handle.

On 13 October 2026, the real OmniAsk production-adapter Windows GPU qualification
passed using the existing Gemma 4 E2B on AMD Radeon integrated graphics: separate
reasoning and answer, checkpoint reopen, and model/tool/result/model execution.
The initial test skill asked ambiguously to "read" a code; the model requested
that code from the user. Clear host-owned/no-input skill instructions yielded
actual execution. This does not prove universal prompt reliability, Android
thinking, or thinking combined with image/audio input.
The same GPU qualification also passed a live Think-off update with unchanged
native history, recall without reasoning afterward, and reopening a saved
Think-on ordinary checkpoint with an explicit Think-off setting. Agent live
Think-off and subsequent recall passed without replaying host calls. A saved
Think-on agent checkpoint also reopened with Think off, retained the host's
verification code, and dispatched no tools during restoration. This qualification
used the actual OmniAsk adapters and Windows GPU, not a mock transport.

## Agent round budgets

Root Rust bounds agent orchestration to 1–32 tool-bearing model rounds per turn.
`OmnixAgentExtensions.maxRounds` is passed through the native registration JSON;
omission by older bridge callers retains four. OmniAsk's existing `maxSteps`
configuration now reaches this control instead of being ignored. The limit does
not measure tokens, individual calls inside a batch, or Workflow plan steps, and
it does not grant tool authority. A Rust six-round sequence succeeds at ten and
stops at four; invalid registration values fail before loading a model.

## Explicit context clearing

Completed agent context can be explicitly cleared by importing an empty portable
history. LiteRT-LM releases the native conversation, not the loaded model, while
preserving settings, tool catalog and effective tool enablement. Nonempty imports
still require a fresh conversation; pending or stopped contexts reject clearing.
Windows GPU qualification passed clearing after a completed tool turn, export
without the old answer, and a new model response. Historical OS actions are never
undone or repeated by clearing context.

## Remaining parity gates

- Backend selection and artifact qualification: root LiteRT-LM CPU/GPU/NPU
  selection is explicit, and Windows GPU has real-model evidence. Android GPU
  packaging is implemented but device inference remains unqualified. NPU
  requires a compatible device/model/vendor dispatch distribution, which is
  not qualified by this integration. Standalone Core Dart backend
  selection and llama.cpp accelerator parity remain work; no silent fallback
  for explicit choices.
- Further native real-model sampling tests, including Android. Rust validation,
  checkpoint checks, Dart transport tests and example widget tests do not replace
  hardware qualification.
- Model/tokenizer accounting and context policies. A larger context selection
  can increase memory requirements; it is not evidence that a device can load it.

These gates remain blockers to claiming complete cross-platform settings parity.
