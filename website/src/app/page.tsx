import Link from "next/link";

const modules = [
  { index: "01", title: "Core + inference", description: "Runtime lifecycle, model management, conversations, context, and fair access to local inference.", state: "Available" },
  { index: "02", title: "Agents + capabilities", description: "Provider-neutral agent sessions backed by a shared registry of tools, skills, and permission policy.", state: "Available" },
  { index: "03", title: "Workflow", description: "Durable tasks, execution state, retries, scheduling policy, and inspectable event history.", state: "Available" },
  { index: "04", title: "Knowledge", description: "Documents, embeddings, retrieval, and explicit access-policy contracts for local knowledge.", state: "Planned" },
  { index: "05", title: "Nexus", description: "Discovery and control contracts for nearby devices, services, and connected environments.", state: "Planned" },
  { index: "06", title: "Rust core", description: "A measured path for moving proven, performance-sensitive components behind stable Dart contracts.", state: "Foundation" },
];

const quickStart = `import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';

final runtime = FlutterGemmaOmnix.createRuntime();
await runtime.initialize();

final conversation = await runtime.openConversation(
  const OmnixConversationConfiguration(
    modelTemplate: OmnixModelTemplate.gemma4,
  ),
);

await for (final event in conversation.send('Hello, locally.')) {
  if (event case OmnixTextDelta(:final text)) print(text);
}`;

export default function Home() {
  return (
    <>
      <section className="hero shell">
        <div className="hero-copy-block">
          <p className="eyebrow"><span className="pulse" /> OPEN ON-DEVICE INTELLIGENCE</p>
          <h1>Build intelligence<br /><span>that stays close.</span></h1>
          <p className="hero-copy">Omnix is an open, headless engine for composing local models, conversations, agents, capabilities, and workflows in Flutter applications.</p>
          <div className="hero-actions">
            <Link className="button" href="/docs">Start building <span aria-hidden="true">&#8594;</span></Link>
            <a className="button quiet" href="https://github.com/omniecosystem/omnix">Explore the source</a>
          </div>
          <div className="release-note"><span>0.1.0-dev.1</span><p>Developer preview. APIs are being stabilized in public.</p></div>
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
          <div><span className="kicker">THE ENGINE LAYER</span><h2>A stable boundary around fast-moving intelligence.</h2></div>
          <p>Applications depend on Omnix contracts. Providers handle model runtimes and agent implementations. Proven internals can move from Dart to Rust without forcing host applications to be rewritten.</p>
        </div>
        <div className="architecture-flow">
          <article><span>HOST</span><strong>Your Flutter app</strong><p>Interface, product policy, accounts, and user experience.</p></article>
          <div className="flow-arrow" aria-hidden="true">&#8594;</div>
          <article className="active-layer"><span>ENGINE</span><strong>Omnix contracts</strong><p>Models, sessions, scheduling, capabilities, and lifecycle.</p></article>
          <div className="flow-arrow" aria-hidden="true">&#8594;</div>
          <article><span>PROVIDERS</span><strong>Runtime adapters</strong><p>Flutter Gemma today, with room for additional providers.</p></article>
        </div>
      </section>

      <section className="section shell" id="modules">
        <div className="section-heading">
          <div><span className="kicker">COMPOSABLE SURFACES</span><h2>Modules shaped by capability, not screens.</h2></div>
          <Link className="text-link" href="/docs#modules">Read the boundaries <span aria-hidden="true">&#8594;</span></Link>
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
          <p>Omnix stays headless. Bring your own presentation and progressively adopt only the engine capabilities your application needs.</p>
          <Link className="button" href="/docs#getting-started">Read the quick start <span aria-hidden="true">&#8594;</span></Link>
        </div>
        <div className="code-window" aria-label="Omnix Dart quick start"><div className="code-header"><span>main.dart</span><span>DART</span></div><pre><code>{quickStart}</code></pre></div>
      </section>

      <section className="section ecosystem-section">
        <div className="shell ecosystem-panel">
          <div><span className="kicker">PART OF THE OMNI ECOSYSTEM</span><h2>Neutral infrastructure. A shared direction.</h2></div>
          <p>Omnix is built as reusable infrastructure for any Flutter product. Within the Omni Ecosystem, it provides the engine beneath user-facing experiences and interoperable capabilities distributed through Omnies.</p>
          <div className="ecosystem-links"><a href="https://omniecosystem.xyz">Visit the ecosystem</a><a href="https://omnies.omniecosystem.xyz">Explore Omnies</a></div>
        </div>
      </section>
    </>
  );
}
