# Flutter Edge AI as a design reference

[Flutter Edge AI](https://github.com/DenisovAV/flutter_edge_ai) is a reference
for on-device inference and agent integration. Omnix uses a Rust-first
architecture and does not require Flutter Edge AI for native execution.

## Capability mapping

| Reference package | Omnix responsibility |
| --- | --- |
| `flutter_edge_ai` | Root composition and public interaction APIs |
| `flutter_edge_ai_litertlm` | Core's LiteRT-LM adapter |
| `flutter_edge_ai_embeddings` | Core embedding execution |
| `flutter_edge_ai_rag` | Knowledge indexing and retrieval |
| `flutter_edge_ai_qdrant`, `flutter_edge_ai_sqlite` | Storage responsibilities, with backend-specific coverage |
| `flutter_edge_ai_agent` | Root agent orchestration and developer-supplied tools and skills |

These are responsibility mappings, not API compatibility or feature-parity
guarantees. Omnix's SQLite persistence is not a claim of SQLite vector-search
support. Additional upstream providers do not imply matching Omnix backends.

## Integration considerations

When moving an application between implementations, compare behavior as well
as API names:

- Model selection, installed artifacts and runtime configuration.
- Cache locations, model/session ownership and release behavior.
- Streaming, cancellation and conversation restoration.
- Tool declarations, skill assets, execution callbacks and result semantics.
- Embedding profiles, storage compatibility and explicit durability operations.
- Target requirements, native packaging and accelerator availability.

Embedding identity includes weights, tokenization and preprocessing conventions,
not just dimensions. Reusing an index requires a compatibility decision.

Product storage migrations are separate from replacing inference APIs.
Preserve existing model files and user data and test upgrades against
representative saved state.

## Versions and licensing

Consult each upstream package's manifest, changelog and documentation for its
version and platform requirements. Versions differ across the package family;
the main package's version does not identify every companion package.

Source references do not replace native ABI checks or license obligations.
Omnix adapters use their own pinned headers and artifact manifests; retained
compatibility identifiers may differ from current product branding.
