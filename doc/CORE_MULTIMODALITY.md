# Core multimodal input

Core exposes an ordered, owned message-parts contract for text, images and audio.
The selected runtime and model must support the requested modalities.

LiteRT-LM media encoders are enabled through native load configuration.
The current llama.cpp text integration does not imply an `mtmd` media adapter.
Neither runtime is an implicit default.

## Responsibilities

| Concern | Owner |
| --- | --- |
| Message parts, input bounds and native inference | Core |
| Encoder/projector dependencies and capability reporting | Core adapter and packaging |
| Artifact integrity and installed state | Core installation |
| Capture, file selection, permissions and playback | Host |
| Retrieval and source attribution | Knowledge |
| Durable conversation coordination | Root Omnix and selected persistence |

Dart exposes the native contract rather than converting media to a textual
description or running a second inference implementation.

## Input contract

```dart
final model = await OmnixCore().loadModel(
  modelPath: trustedModelPath,
  enableImages: true,
  enableAudio: false,
);
try {
  final conversation = await model.startConversation(maxOutputTokens: 128);
  try {
    final answer = await conversation.sendMessage([
      OmnixInputPart.text('Describe this image.'),
      OmnixInputPart.image(encodedImageBytes),
    ]);
  } finally {
    await conversation.close();
  }
} finally {
  await model.close();
}
```

Enabling an encoder is configuration, not proof that the artifact contains it.
Unsupported capabilities must fail rather than silently discard input.

Current chat admission bounds include at most 16 parts, four images, one WAV,
1 MiB of text and 16 MiB of encoded media per turn.
PNG/JPEG images are limited to 8 MiB each, 4096 pixels per axis and 16 million
pixels. Audio requires PCM16 mono 16 kHz WAV, up to 60 seconds.
These bounds do not guarantee that a request fits the model's context capacity.

## Lifetime and history

Own input bytes through native completion and cancellation drain.
A temporary picker path alone is not replay-safe history.
The native JSON ABI uses base64 and serialization allocations; this is not a
zero-copy media interface.

Supported restoration depends on the adapter and format.
Never replace media context with lossy text-only history without an explicit
unsupported result or application decision.

## Beyond turn-based input

A video container requires host decoding and a supported frame/time contract.
Sending a video filename to an image API is not video inference.
Continuous audio, full-duplex interaction and output audio require separate
runtime contracts.

## Validation

Test ordered mixed input, encoder selection, content validation, cancellation,
recall and native ownership. Test image understanding and spoken input with
representative models, not merely successful serialization.

Synthetic image/audio fixtures test admission and selected behaviors, not
general accuracy. Text-only tests do not qualify a multimodal agent loop.

See [Core compatibility](CORE_PARITY.md),
[EmbeddingGemma 2](EMBEDDINGGEMMA_2.md), and
[live interaction direction](LIVE_INTERACTION_DIRECTION.md).
