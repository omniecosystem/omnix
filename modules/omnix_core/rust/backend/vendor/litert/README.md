# LiteRT embedding C headers

Unmodified Apache-2.0 upstream headers from Google AI Edge LiteRT revision
`9fe5be45564c868408e6514c8aabb83e211a0911`, the LiteRT dependency pinned by
LiteRT-LM v0.17.1's WORKSPACE. Source:
https://github.com/google-ai-edge/LiteRT/tree/9fe5be45564c868408e6514c8aabb83e211a0911/litert/c

These declare the tensor forward-pass API; they are not a Dart implementation
or another inference engine. The standalone maintainer generator binds only
the implemented CPU embedding surface. Its include-only build_config.h disables
optional accelerator declarations; it does not build or configure a runtime.
The runtime remains the selected, pinned LiteRT native distribution.

Generated concrete tensor layouts presently require Windows x64 qualification.
Symbol presence alone does not prove compatibility with another runtime ABI.
