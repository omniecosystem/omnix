# One Home, native orchestration

The root Flutter example uses root Omnix sessions and agents for its shared
Home interaction. Standalone module examples remain independent.
The example's repositories adapt UI and history; they do not implement a
second inference or agent loop.

## Input and execution

Root sessions expose text, image and audio input through native contracts.
Core validates capabilities and supported input formats. Acceptance depends on
the selected model, runtime and target; a shared input API does not imply
identical support across backends.

Root Omnix coordinates agent planning, tool policy, dispatch and cancellation.
Flutter provides capture, file selection, playback and approval presentation.
Those host functions do not belong in the inference runtime.

Knowledge can supply retrieved information to the same interaction rather
than requiring a separate chat interface. Its configuration and resource
ownership remain explicit.

## Persistence

Displayed transcripts and native runtime checkpoints have different purposes.
Hosts must preserve the conversation's supported content and handle unsupported
restoration explicitly. A text-only snapshot must not silently replace media
or tool context.

The example includes a migration from `native-chat-history.sqlite` to
`composed-chat-history.sqlite`. Existing source records are not a license
to overwrite conversations already continued in the destination.

Storage format compatibility and supported restore content depend on the
current implementation. Test representative records before upgrading a
consumer database.

## Integration validation

Exercise text, supported media combinations, tool results, cancellation,
follow-up turns, switching and restore using compatible models.
Do not interpret a successful build or a UI test as native execution evidence.

See [example architecture](EXAMPLE_ARCHITECTURE.md) and
[integration validation](MIGRATION_QUALIFICATION.md).
