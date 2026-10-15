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
          <span className="kicker">01 / GETTING STARTED</span><h2>Run your first local example</h2>
          <p>Start from a current source checkout with Flutter, Rust and Windows build tools installed. The root example lets you explore local conversations and the available modules. You will need a compatible local model; follow the example README for model files and build prerequisites.</p>
          <pre><code>{install}</code></pre>
          <p>Core runtimes, Storage backends and Nexus protocols are explicitly selected. Rust modules can be consumed independently of their Flutter bindings.</p>
          <pre><code>{runtime}</code></pre>
        </section>

        <section className="docs-section" id="developer-path">
          <span className="kicker">ONE IMPLEMENTATION, TWO ENTRY POINTS</span><h2>Native control. Approachable APIs.</h2>
          <p>Rust developers can use the independent module crates directly or select capabilities through the Omnix facade. You own lifecycle and host integration without depending on Dart or Flutter.</p>
          <p>Dart developers can use individual module packages or the composed Omnix API. Both expose the same Rust implementation, including agent orchestration and workflow execution. In a Flutter application, you supply the interface, media capture, permissions and OS integration.</p>
          <p>Start with Core for one local model. Add Storage, Knowledge, Workflow or Nexus when the application needs them. Choose Omnix when you want those capabilities composed behind one system API. No account or marketplace is required for standalone use.</p>
          <div className="notice"><strong>The API promise</strong><p>Choose your capabilities, receive streaming events and control resource lifecycles through explicit APIs. Unsupported operations return clear errors. APIs may change during the developer preview; check the runtime and platform notes when planning your integration.</p></div>
        </section>

        <section className="docs-section" id="architecture">
          <span className="kicker">02 / ARCHITECTURE</span><h2>Clear contracts, replaceable internals</h2>
          <div className="docs-callout"><strong>Host application</strong><span>&#8594;</span><strong>Omnix API</strong><span>&#8594;</span><strong>Provider adapters</strong><span>&#8594;</span><strong>Model runtime</strong></div>
          <p>Public Dart contracts are handwritten, so you can use them without working with generated bridge code. Rust-only applications have no Flutter dependency. Omnix composes optional agent capabilities; Core runs models, Workflow manages durable tasks, and Nexus checks remote authority before dispatch.</p>
        </section>

        <section className="docs-section" id="extensions">
          <span className="kicker">DEVELOPER GUIDE</span><h2>Build a Cognitive System</h2>
          <p>Embed Omnix in your application, service or device. Supply capabilities through public tool definitions and host callbacks, select skill instructions and grant access explicitly. Rust owns the agent loop; your host owns OS integration, consent and the interface. You do not need to understand generated bridge code or internal orchestration.</p>
          <p>Use OmnixAgentExtensions to supply tools and skills for the optional agent capability. Tools execute callbacks provided by your host; skills describe how to use them. Skill instructions do not grant device permissions or install executable code. Character profiles and downloadable executable extensions are not currently available.</p>
          <p>Build an end-user experience like OmniAsk, or embed Omnix in your own product. If your app accepts resources from Omnies or another catalog, validate their compatibility and request any required permissions in your host. Neither OmniAsk nor an Omnies account is required to embed Omnix.</p>
          <div className="notice"><strong>Integration notes</strong><p>You can combine media input and tools when your chosen model and runtime support them. Rust handles validation, execution bounds and session state; your host supplies callbacks, storage configuration, permissions and OS services. Background execution is subject to the target operating system&apos;s limits.</p></div>
        </section>

        <section className="docs-section" id="modules">
          <span className="kicker">03 / MODULES</span><h2>Capability boundaries</h2>
          <p>Select the capabilities your application needs. Each module can be used independently or combined through the Omnix API.</p>
          <div className="module-table">
            {moduleRows.map(([name, responsibility, state]) => <div key={name}><strong>{name}</strong><span>{responsibility}</span><em>{state}</em></div>)}
          </div>
        </section>

        <section className="docs-section" id="roadmap">
          <span className="kicker">PLATFORM ROADMAP</span><h2>Beyond the current native integrations.</h2>
          <p>Linux and browsers are future OmniAsk targets. Planned browser integrations include JavaScript or WebAssembly model runtimes, with LiteRT-LM and llama.cpp as candidate paths, plus browser-compatible storage and networking.</p>
          <p>A browser app is the first web milestone; an extension for browser automation is a later direction. iOS, macOS and Safari are also on the roadmap. These integrations are not yet available as supported end-to-end targets.</p>
          <p>Nexus can also connect systems that do not embed the rest of Omnix. We are exploring Rust libp2p for connectivity across consumer networks, alongside A2A messaging and local access controls. libp2p is not currently integrated.</p>
        </section>

        <section className="docs-section" id="status">
          <span className="kicker">04 / RELEASE STATUS</span><h2>What the preview means</h2>
          <p>Omnix now powers OmniAsk. You can explore local inference, streamed agents, host tools, knowledge retrieval and durable workflows through its developer-preview APIs. Feature availability depends on your model, runtime, device and host integration.</p>
          <div className="module-table">
            <div><strong>Android</strong><span>LiteRT-LM powers the current OmniAsk integration, including compatible Gemma image/audio input and host tools. OS permissions and background limits still apply.</span><em>Product integration</em></div>
            <div><strong>Windows</strong><span>Try native examples for LiteRT-LM and llama.cpp text generation, persistence and retrieval. Model and accelerator compatibility varies.</span><em>Native examples</em></div>
            <div><strong>CPU / GPU</strong><span>Select a backend where your runtime supports it. GPU availability and performance depend on your device. General NPU support is not yet available.</span><em>Device-dependent</em></div>
            <div><strong>Other targets</strong><span>iOS, macOS, Linux, web and embedded integrations are not currently supported end to end. Follow the platform roadmap for future availability.</span><em>Future integrations</em></div>
            <div><strong>Nexus</strong><span>Explore A2A exchanges and experimental Matter controller adapters. Production networking and smart-home integrations are not yet available.</span><em>Experimental</em></div>
          </div>
          <div className="notice"><strong>Plan your integration</strong><p>Find build prerequisites, runtime compatibility notes and tested configurations in the repository. <a href="https://github.com/omniecosystem/omnix/tree/main/doc" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Explore the technical documentation</a>.</p></div>
        </section>
      </article>
    </div>
  );
}
