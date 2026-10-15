import Link from "next/link";

const modules = [
  { index: "01", title: "Core", description: "Select LiteRT-LM or llama.cpp for local inference. Streaming, cancellation, runtime controls and embeddings; multimodal input depends on the model and adapter.", state: "Preview" },
  { index: "02", title: "Agents + capabilities", description: "Rust-owned streaming model/tool loops with host-supplied tools, skills and execution policies. Optional composition in Omnix, not a separate inference runtime.", state: "Preview" },
  { index: "03", title: "Workflow", description: "Durable execution state, step results, retry rules and recovery. Hosts provide triggers and OS scheduling; Android has an example scheduling adapter.", state: "Preview" },
  { index: "04", title: "Knowledge", description: "Index local sources, select embedding profiles and retrieve relevant context with source attribution for your model.", state: "Preview" },
  { index: "05", title: "Nexus", description: "Paired A2A communication and authority checks; Matter controller integration remains experimental.", state: "Experimental" },
  { index: "06", title: "Storage", description: "Persist structured records with SQLite and embedding vectors with Qdrant. Choose either backend independently or use both.", state: "Preview" },
];

const quickStart = `import 'package:omnix_core/omnix_core.dart';

// Select runtimes in the app's native build configuration.
final core = OmnixCore();
final model = await core.loadModel(modelPath: trustedModelPath);
try {
  final chat = await model.startConversation();
  try {
    await for (final text in chat.sendStream('Hello, locally.')) {
      print(text);
    }
  } finally {
    await chat.close();
  }
} finally {
  await model.close();
}`;

export default function Home() {
  return (
    <>
      <section className="hero shell">
        <div className="hero-copy-block">
          <p className="eyebrow"><span className="pulse" /> OPEN ON-DEVICE COGNITIVE SYSTEM</p>
          <h1>Give your device<br /><span>a cognitive foundation.</span></h1>
          <p className="hero-copy">Build local AI applications with a Rust-owned foundation for model execution, conversations, tools, knowledge and workflows. Use Omnix to compose capabilities, or use its modules independently through Rust and Dart APIs.</p>
          <div className="hero-actions">
            <Link className="button" href="/docs">Start building <span aria-hidden="true">&#8594;</span></Link>
            <a className="button quiet" href="https://github.com/omniecosystem/omnix" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Explore the source</a>
          </div>
          <div className="release-note"><span>DEVELOPER PREVIEW</span><p>Now powers OmniAsk. Explore the same foundation in your own applications. APIs may change during the preview; check compatibility for your runtime and target platform.</p></div>
        </div>

        <div className="engine-visual" aria-label="Omnix architecture preview">
          <div className="orbit orbit-one" /><div className="orbit orbit-two" />
          <div className="engine-core"><span className="core-label">OMNIX</span><strong>LOCAL</strong><small>RUNTIME</small></div>
          <span className="satellite satellite-model">MODELS</span>
          <span className="satellite satellite-agent">AGENTS</span>
          <span className="satellite satellite-flow">WORKFLOW</span>
        </div>
      </section>

      <section className="signal-strip" aria-label="Omnix principles">
        <div className="shell signals"><span>LOCAL-FIRST</span><i /><span>PROVIDER-NEUTRAL</span><i /><span>HEADLESS BY DESIGN</span><i /><span>OPEN SOURCE</span></div>
      </section>

      <section className="section shell" id="architecture">
        <div className="section-heading split-heading">
          <div><span className="kicker">THE COGNITIVE SYSTEM</span><h2>Composable capabilities. Explicit boundaries.</h2></div>
          <p>Choose the capabilities your application needs, with shared behavior implemented in Rust. Keep your own interface, consent flow and OS integration while Omnix coordinates local models, tools and tasks.</p>
        </div>
        <div className="architecture-flow">
          <article><span>HOST</span><strong>Your app or service</strong><p>Interface, consent, permissions and OS integration.</p></article>
          <div className="flow-arrow" aria-hidden="true">&#8594;</div>
          <article className="active-layer"><span>SYSTEM</span><strong>Omnix composition</strong><p>Rust-owned orchestration over explicitly selected modules, exposed through Rust and Dart APIs.</p></article>
          <div className="flow-arrow" aria-hidden="true">&#8594;</div>
          <article><span>BACKENDS</span><strong>Proven native libraries</strong><p>Explicitly selected model runtimes, stores and protocols.</p></article>
        </div>
      </section>

      <section className="section shell" id="modules">
        <div className="section-heading">
          <div><span className="kicker">COMPOSABLE CAPABILITIES</span><h2>Start with one module. Build your system.</h2></div>
          <Link className="text-link" href="/docs#modules">Explore the modules <span aria-hidden="true">&#8594;</span></Link>
        </div>
        <div className="module-grid">
          {modules.map((module) => (
            <article className="module-card" key={module.title}>
              <div className="module-top"><span className="module-index">{module.index}</span><span className={`status status-${module.state.toLowerCase()}`}>{module.state}</span></div>
              <div><h3>{module.title}</h3><p>{module.description}</p></div>
            </article>
          ))}
        </div>
      </section>

      <section className="section shell quickstart-section">
        <div className="quickstart-copy">
          <span className="kicker">START SMALL</span><h2>One runtime. One conversation. Your interface.</h2>
          <p>Omnix stays headless. Bring your own presentation and adopt only the capabilities you need. This native Core example requires a configured build and trusted local model.</p>
          <Link className="button" href="/docs#getting-started">Read the quick start <span aria-hidden="true">&#8594;</span></Link>
        </div>
        <div className="code-window" aria-label="Omnix Dart quick start"><div className="code-header"><span>main.dart</span><span>DART</span></div><pre><code>{quickStart}</code></pre></div>
      </section>

      <section className="section ecosystem-section">
        <div className="shell ecosystem-panel">
          <div><span className="kicker">PART OF THE OMNI ECOSYSTEM</span><h2>Neutral infrastructure. A shared direction.</h2></div>
          <p>OmniAsk uses Omnix for its local AI backend. Try the example application to explore capabilities before integrating them into your own product. You can use Omnix without OmniAsk, an account or a marketplace, or choose standalone Omnix Core for model execution.</p>
          <div className="ecosystem-links"><a href="https://omniecosystem.xyz" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Visit the ecosystem</a><a href="https://omnies.omniecosystem.xyz" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Explore Omnies</a></div>
        </div>
      </section>
    </>
  );
}
