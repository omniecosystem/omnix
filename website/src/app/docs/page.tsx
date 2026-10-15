import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Documentation",
  description: "Explore the Omnix Rust-first, on-device Cognitive System.",
};

const install = `cd example
flutter pub get
flutter run -d windows`;

const runtime = `Host app / service
    → Handwritten API (Rust or Flutter binding)
    → Selected Rust modules
    → Native runtime / database / protocol`;

const moduleRows = [
  ["Core", "Model execution, streamed text, cancellation, embeddings", "Native preview"],
  ["Storage", "SQLite records and Qdrant vectors", "Native preview"],
  ["Agents", "Optional root composition: model/tool loop, skills and host callbacks", "Native preview"],
  ["Workflow", "Durable steps, retry rules, results and recovery; host-owned triggers", "Native preview"],
  ["Knowledge", "Profile-bound indexes, attributed retrieval", "Native preview"],
  ["Nexus", "Paired A2A access; experimental Matter", "Experimental"],
];

export default function DocsPage() {
  return (
    <div className="docs-layout shell">
      <aside className="docs-nav" aria-label="Documentation sections">
        <span>DOCUMENTATION</span>
        <a href="#overview">Overview</a><a href="#getting-started">Getting started</a><a href="#developer-path">Rust and Dart</a><a href="#architecture">Architecture</a><a href="#extensions">Developer extensions</a><a href="#modules">Modules</a><a href="#status">Release status</a><a href="#roadmap">Roadmap</a>
      </aside>
      <article className="docs-content">
        <header className="docs-hero" id="overview">
          <p className="eyebrow"><span className="pulse" /> DEVELOPER PREVIEW</p>
          <h1>Build with Omnix.</h1>
          <p>Omnix is a modular Cognitive System for OS-hosted applications and services. Rust owns reusable behavior; Dart bindings make selected capabilities accessible without requiring Rust knowledge. The host retains presentation, consent and OS integration. Its standalone Core module provides the Cognitive Engine for model execution.</p>
        </header>

        <section className="docs-section" id="getting-started">
          <span className="kicker">01 / GETTING STARTED</span><h2>Run the native proving ground</h2>
          <p>The native-module work is under active development and differs from earlier published previews. From a current source checkout with Flutter, Rust and Windows build tools installed, run the root example. Model execution requires a trusted local model; see the repository example README for artifact and build prerequisites.</p>
          <pre><code>{install}</code></pre>
          <p>Core runtimes, Storage backends and Nexus protocols are explicitly selected. Rust modules can be consumed independently of their Flutter bindings.</p>
          <pre><code>{runtime}</code></pre>
        </section>

        <section className="docs-section" id="developer-path">
          <span className="kicker">ONE IMPLEMENTATION, TWO ENTRY POINTS</span><h2>Native control. Approachable APIs.</h2>
          <p>Rust developers can use the independent module crates directly or select capabilities through the Omnix facade. You own lifecycle and host integration without depending on Dart or Flutter.</p>
          <p>Dart developers use handwritten module packages or the composed Omnix API over the same Rust behavior. Generated bridge code stays internal. Flutter is a consumer for UI, capture, permissions and OS integration, not a second agent loop or workflow engine.</p>
          <p>Start with Core for one local model. Add Storage, Knowledge, Workflow or Nexus when the application needs them. Choose Omnix when you want those capabilities composed behind one system API. No account or marketplace is required for standalone use.</p>
          <div className="notice"><strong>The API promise</strong><p>Explicit capability selection, clear unsupported-operation errors, streaming events and owned resources. The API is still evolving; backend or target limitations must remain visible rather than hidden behind a claim of universal support.</p></div>
        </section>

        <section className="docs-section" id="architecture">
          <span className="kicker">02 / ARCHITECTURE</span><h2>Stable contracts, replaceable internals</h2>
          <div className="docs-callout"><strong>Host application</strong><span>&#8594;</span><strong>Omnix API</strong><span>&#8594;</span><strong>Provider adapters</strong><span>&#8594;</span><strong>Model runtime</strong></div>
          <p>Public Dart contracts are handwritten; generated bridge details stay internal. Rust-only consumers do not depend on Flutter. Optional agent orchestration belongs in Omnix composition, while Core runs models, Workflow manages durable tasks, and Nexus checks remote authority before dispatch.</p>
        </section>

        <section className="docs-section" id="extensions">
          <span className="kicker">DEVELOPER GUIDE</span><h2>Build a Cognitive System</h2>
          <p>Embed Omnix in your application, service or device. Supply capabilities through public tool definitions and host callbacks, select skill instructions and grant access explicitly. Rust owns the agent loop; your host owns OS integration, consent and the interface. You do not need to understand generated bridge code or internal orchestration.</p>
          <p>OmnixAgentExtensions configures the optional agent capability, not a universal plugin system. Tools execute host capabilities; skills describe how to use them. Installing instructions never grants authority. Character profiles and general downloadable executable extensions are not implemented.</p>
          <p>End users use a consumer such as OmniAsk. Omnies is the catalog and distribution layer; the consumer must validate compatibility and permissions before installing a package. Neither OmniAsk nor an Omnies account is required to embed Omnix.</p>
          <div className="notice"><strong>Current limits</strong><p>Media input and tools can be combined with a compatible model and runtime; this is not parity across all adapters. Rust owns validation, bounded execution and session state. Hosts supply trusted callbacks, storage configuration, permissions and OS services. Downloaded skill instructions cannot install arbitrary executable code, and mobile operating systems still constrain background work.</p></div>
        </section>

        <section className="docs-section" id="modules">
          <span className="kicker">03 / MODULES</span><h2>Capability boundaries</h2>
          <p>Modules follow reusable engine responsibilities rather than copying the navigation of any host application.</p>
          <div className="module-table">
            {moduleRows.map(([name, responsibility, state]) => <div key={name}><strong>{name}</strong><span>{responsibility}</span><em>{state}</em></div>)}
          </div>
        </section>

        <section className="docs-section" id="roadmap">
          <span className="kicker">PLANNED, NOT PLATFORM SUPPORT CLAIMS</span><h2>Beyond the current native integrations.</h2>
          <p>Linux and browser support are future OmniAsk targets. Browser inference requires suitable runtime adapters: evaluate the LiteRT-LM JavaScript route and a llama.cpp browser equivalent, alongside web-compatible storage and networking. A Rust/Wasm build alone does not supply the browser model runtime.</p>
          <p>Begin with a browser app, potentially at omniask.omniecosystem.xyz; browser automation through an extension is a separate later integration. iOS, macOS and Safari also need native or browser-specific packaging, runtime and lifecycle evidence before being advertised as supported.</p>
          <p>Nexus remains independently usable by systems that do not embed the rest of Omnix. Evaluate optional Rust libp2p reachability for consumer networks without replacing A2A messages or confusing transport with authorization.</p>
        </section>

        <section className="docs-section" id="status">
          <span className="kicker">04 / RELEASE STATUS</span><h2>What the preview means</h2>
          <p>Omnix now powers OmniAsk, while its reusable APIs remain a developer preview. Local inference, streamed agents, host tools, knowledge retrieval and durable workflow execution are implemented; qualification is specific to a model, runtime, device and host integration.</p>
          <div className="module-table">
            <div><strong>Android</strong><span>LiteRT-LM powers the current OmniAsk integration, including compatible Gemma image/audio input and host tools. OS permissions and background limits still apply.</span><em>Product integration</em></div>
            <div><strong>Windows</strong><span>Native examples exercise LiteRT-LM and llama.cpp text execution, persistence and retrieval. This does not qualify every model or accelerator.</span><em>Tested slices</em></div>
            <div><strong>CPU / GPU</strong><span>Backend controls are exposed where the runtime supports them. GPU availability and benefit depend on the device; NPU is not generally qualified.</span><em>Device-dependent</em></div>
            <div><strong>Other targets</strong><span>iOS, macOS, Linux, web and embedded targets need their own end-to-end qualification. Compiling Rust alone is not platform support.</span><em>Not generally qualified</em></div>
            <div><strong>Nexus</strong><span>A2A exchange and Matter controller adapters have experimental evidence, not a production networking or smart-home guarantee.</span><em>Experimental</em></div>
          </div>
          <div className="notice"><strong>Evaluate the source, not a promise of universal support.</strong><p>The public API is evolving. Review build prerequisites and qualification notes before adopting a module in your own product. <a href="https://github.com/omniecosystem/omnix/tree/main/doc" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Read the engineering evidence</a>.</p></div>
        </section>
      </article>
    </div>
  );
}
