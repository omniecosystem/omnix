# Mixed-input Home chats

Home's native ordinary and agent conversations can start with text and accept voice or images later. On the
first additional input type, the host exports completed native context, releases
the old session, loads the requested encoders, and restores that context. It does
not replay tools, ask the model to reconstruct history, or silently transcribe
audio into a separate text-only chat. Models must actually support the requested
encoder; unsupported loads fail explicitly.

The composer accepts image + recorded WAV + optional text in the same request.
An empty draft uses its main microphone button. With text or attachments present,
a separate microphone control keeps recording accessible beside Send. Stop
recording adds the WAV to the unsent draft; only Send submits the combined parts.
Recording is disabled while one audio attachment is already present. Uploads and
recordings share limits: four images, one WAV, 16 MiB combined, 8 MiB per image,
and 2 MiB per WAV. A rejected recording leaves existing draft attachments intact.
Combined model execution still requires both encoders and device qualification.

Rust validates owned media in agent checkpoints using the same admission checks
as new input: valid bounded WAV/images, bounded text, and balanced tool calls and
results. File paths, URLs and malformed blobs are rejected. Checkpoints are
context, not authorization. Restored tool results do not execute host actions or
carry approvals forward. Current tool declarations and conversation settings
must still match.

The example saves the native checkpoint and enabled input types. Reopening loads
the matching encoders before restoring context. Display history uses attachment
names for attachment-only turns; replay/playback thumbnails are not yet restored.
Media bytes are held in the private checkpoint, not duplicated as presentation
attachments. Keep this database private: recordings/images and tool data are
sensitive, and the database is not encrypted by this change.

Limits: native context checkpoint 16 MiB, root envelope 20 MiB, example snapshot
24 MiB, and at most 200 native messages. Long media histories can reach these
limits. A failed save blocks blind continuation because tools may already have
run; automatic pruning/retention remains follow-up work.

Ordinary chats retain the version-1 text history format and introduce version-2
native media context through the existing history API. Their stored UI transcript
is separate and is never used to reconstruct version-2 inference context. Saved
encoder flags are restored before loading the conversation. Settings changes
refresh the native context before committing metadata. Failed ordinary saves
release incomplete context and retain the last successfully saved conversation.

Scope: LiteRT-LM native ordinary and agent chats. Custom agent transports must provide
both media input and checkpoint support; custom ordinary transports must explicitly
opt into durable media. Older custom transports retain temporary media behavior. This does not
claim llama.cpp agent parity or Android/Windows packaged-app qualification.

Qualification: rebuild the example (Rust changed), test with and without the agent, send a text
fact, send a voice follow-up, then add an image. Check previous context is retained.
Reopen from History, continue by voice and text, and check that earlier tools
are not called merely because the conversation was restored. No model downloads
or clearing app data are required.
