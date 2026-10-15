# Omnix website direction

Omnix is presented as a Cognitive System; standalone Core as the Cognitive
Engine. APIs should use stable product names rather than encode marketing terms.

The developer promise is one Rust-owned implementation with native Rust APIs
and approachable handwritten Dart APIs. A developer can use a module alone or
choose Omnix composition. Explain selection, capability discovery, resources,
streaming, cancellation, diagnostics and platform limits without requiring
knowledge of generated bridge internals. Do not create a second Dart agent or
workflow engine merely to make the interface convenient.

Planned coverage includes Linux and browser paths for OmniAsk, including a
LiteRT-LM JavaScript adapter candidate and a llama.cpp browser equivalent.
Storage, Knowledge, Nexus and Workflow require suitable browser adapters too.
Web app first; browser automation through an extension is a distinct later host.
iOS, macOS and Safari need their own runtime, packaging and lifecycle evidence.

Nexus must remain independently usable by non-Omnix systems. Optional libp2p
reachability may be evaluated there without replacing A2A or local authority.
Characters/tools are a consumer/catalog roadmap, not hardcoded engine features.
No delivery dates or universal platform guarantees are implied.
