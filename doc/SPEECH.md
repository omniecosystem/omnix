# Audio and speech boundary

Omnix does not equate speech support with one provider package. A host may need
one or more distinct capabilities:

1. **Direct model audio understanding** sends audio to a multimodal inference
   model. Current Flutter Gemma inference supports whole 16 kHz mono WAV input
   for compatible Gemma models on native platforms.
2. **Speech-to-text** produces a reusable transcript for dictation, indexing,
   accessibility, or models that do not accept audio.
3. **Text-to-speech** synthesizes an assistant response. Direct audio input to
   a model does not provide this capability.
4. **Platform speech services** may satisfy either direction without another
   downloaded model, subject to availability and privacy policy.

The future Omnix speech boundary should describe the requested capability and
let composition select the best available provider. Direct model audio should
be preferred when it satisfies the interaction and privacy requirements.
Dedicated speech packages remain optional adapters for transcription,
synthesis, unsupported models, or platform-specific needs.

Omnix must therefore not add `flutter_gemma_speech` as a mandatory dependency
merely to support voice input. Before exposing audio publicly, the core message
contract also needs a neutral audio attachment type, format validation, model
capability discovery, and platform-availability reporting.

A host that uses `flutter_gemma_speech` can attach `VoiceSession.custom` through
its engine-independent responder callbacks. It should not need to extract a
provider-native chat object from Omnix merely to stream text and stop a turn.
