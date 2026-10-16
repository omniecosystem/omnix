# Working context and durable conversation history

## Current support

Automatic context budgeting is **unsupported for the bundled LiteRT-LM adapter**.
Enabling it through `configureContext()` returns
`context-accounting-unsupported:litertlm`. Requesting `contextUsage()` returns the
same explicit error. Disabling the policy is a no-op between completed turns.
Neither operation fabricates token counts or changes stored history.

The example no longer enables this policy. Ordinary inference, native context
capacity and output-token controls remain available. There is no automatic
history eviction or summarization. Native capacity failures remain possible and
must be surfaced rather than hidden behind a guessed fit prediction.

The previous character-count conversion has been removed. Its Windows smoke
test demonstrated native replay and persistence, not reliable token accounting,
and is not evidence that automatic budgeting is supported. The replacement
native test checks explicit rejection, unchanged history and subsequent inference.

## Boundaries

Omnix owns selection policy in `rust/src/context.rs`. Its deterministic selector
operates on supplied costs; it is not a tokenizer and is not currently enabled
for live LiteRT-LM admission. Core adapters must provide reliable native
accounting and runtime capacity checks before this policy can be used. Storage
owns durability. Consumers present diagnostics, not a second trimming algorithm.

The selector preserves complete user/tool exchanges and does not delete stored
messages. Mandatory instructions, tool schemas, the incoming request and active
tool rounds cannot be evicted. Those rules are tested as budget arithmetic over
explicit supplied costs, not as verified model token counts.

Checkpoint validation permits up to 10,000 messages within existing byte limits;
this is a storage validation bound, not evidence that the model can replay that
many messages. LiteRT-LM turn admission retains its 200-message bound and native
capacity checks. Restore retains validated history and defers replay until the
next send. Recovery replays the complete history, without heuristic selection.

## Required qualification

The local official LiteRT-LM headers declare engine tokenization and a
conversation KV-cache token-count API. Inspection of the current Windows
`LiteRtLm.dll` export table confirms `litert_lm_engine_tokenize`, its result
accessors, and `litert_lm_conversation_get_token_count` are present. This is
export verification, not behavioral qualification. Their semantics, complete
chat-template framing, tool schemas and incoming multimodal payload accounting
must be verified before enabling automatic budgeting. Other packaged platforms
still need export checks.

llama.cpp exposes tokenization, but complete formatted-prompt accounting still
needs integration and qualification. Counting plain message strings separately
is not sufficient. Neither runtime currently supplies a qualified automatic
context selector in Omnix. Summarization and long-context text/tool/media
qualification remain pending.
