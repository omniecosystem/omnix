# Switching tool capabilities between turns

The Rust `ToolConversation::set_tools_enabled(bool)` boundary and root
`AgentSession::set_tools_enabled(bool)` now support a LiteRT-LM capability
change on an existing tool-capable session. Other providers explicitly report
unsupported until implemented and qualified.

Disabling tools recreates the native conversation with an empty declaration
catalog and constrained tool decoding disabled. Re-enabling uses only the
catalog originally supplied by the host. Model weights and the owning worker
stay loaded; completed native text/media and tool exchanges remain context.
Restoration never invokes an executor, evaluates a policy, or grants approval.
The existing host executor and policy still govern future tool calls.

Changes are rejected while tool results are pending, after an interrupted
turn, or when enabling without a supplied catalog. Configuration and history
are retained if native recreation fails; the next recovery uses the previous
configuration. Upstream supports one live conversation, so recreation releases
the native conversation handle first, not the model engine.

Checkpoints retain the full supplied catalog for historical validation and
include a strictly boolean `toolsEnabled` state. Older checkpoints without that
field remain enabled. Future turns are validated only against active tools;
historical calls are validated against the supplied catalog, not treated as
new executable requests. Sampling reconfiguration and native recovery retain
the enabled state.

The Dart bridge exposes `OmnixAgentSession.setToolsEnabled` and
`importChatHistory`, serialized against other operations on that session.
Core's Conversation options permits changing **Tools in all conversations**
between turns. This is an app-wide host preference, enabled by default in the
developer example and persisted in its private application-support directory.
Switching chats does not restore a conversation-specific preference. Selecting
an older ordinary chat with tools available upgrades its native history before
continuation. Agent checkpoints are restored first, then the current host
availability is applied before any inference. Failed preference saves roll back
the active session's availability.

Each consumer remains responsible for its account entitlement. Derive
availability from current access, not from this example's
preference or a saved checkpoint. Account access and autonomy are separate:
enabling tools neither grants new tools nor bypasses the supplied approval policy.
The root Rust/Dart APIs retain per-session controls for custom consumers; the
example repository also retains its standalone per-conversation mode when the
host does not opt into `sharedToolAvailability`.
Host-backed chats retain the same native agent session when tools are disabled;
this is ordinary inference with no advertised tools, not a second transcript.
Saved metadata includes the enabled state, which defaults to enabled for older
agent snapshots.

Existing ordinary chats are explicitly migrated on first enable. The example
exports actual native history (never display text), releases the old model
owner, opens a tool-capable session with the saved model/settings/encoder flags,
and asks Rust to import completed ordinary context. Native import rejects
tool-bearing history, incomplete exchanges, disabled media modalities, and
non-fresh targets. The new agent's system instructions and supplied tools apply
to subsequent turns. Previous media and completed text stay context.

The ID and displayed transcript are retained. The initial ordinary-to-agent
migration may reload the model; subsequent availability changes only recreate
the native conversation. The UI commits the new mode only after native success
and durable save. A failed write rolls back native availability. If rollback
fails, continuation is blocked until reopening a saved conversation. Failed
ordinary migration retains the old saved ordinary record and restores its
presentation state. Historical intents are not made actionable by restoration.

Qualification on Android and Windows remains required, especially ordinary
media-to-agent import, disabled-tool history replay, repeated toggles, and
reopening after settings changes. This does not claim llama.cpp agent parity.

## Home presentation and startup

Conversation controls, autonomy, email proposals and the optional Knowledge
source control live in Core. Home has no mode badge, readiness badge, options
button or loading progress bar. Readiness and manual preparation are available
in Core for troubleshooting.

The example starts eager preparation without blocking the Home screen. Users
can type, attach or record while the model prepares. Sending immediately adds
the user bubble and an animated three-dot response placeholder; one submitted
turn waits for the existing preparation to finish before inference starts.
Duplicate submission and conversation/settings changes remain blocked during
that wait. Stop cancels the waiting turn (it does not claim to interrupt a native
model load); closing drains preparation before releasing ownership. A load
failure leaves the submitted message visible with the error and no inference.
This waiting turn is in-memory UI state, not a durable background workflow.

## Try it

Rebuild the example with the normal launch command (Rust and generated bindings
changed; hot reload alone is insufficient). No uninstall or data clearing is
required. In Home:

1. Turn Tools in all conversations off; ask it to remember a harmless unique fact.
2. Open Core → Conversation options and enable Tools in all conversations in the same chat.
3. Ask for the current time and confirm actual tool activity.
4. Disable tools; ask it to recall the fact. Confirm no tool activity.
5. Open another chat and return. Confirm the toggle stays off and recall works.
6. Enable again and try an audio/image follow-up with a supporting model.
7. Restart the example. Confirm the app-wide setting survives, regardless of
   the enabled state last saved inside each individual conversation.

Unit tests cover availability, legacy and disabled checkpoint restoration,
historical call/result preservation, rejecting new disabled calls, pending-turn
guards, ownership forwarding, and root orchestration without executor/policy
callbacks. Dart tests additionally cover same-ID migration, reopen, no extra
model loads for availability changes, failed-import/write rollback, and Home's
toggle after completed messages. They do not replace real-model/device qualification.
