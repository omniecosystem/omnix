import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Documentation",
  description: "Start building with the Omnix on-device intelligence engine.",
};

const install = `dependencies:
  omnix: ^0.1.0-dev.1`;

const runtime = `import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';

final runtime = FlutterGemmaOmnix.createRuntime();
await runtime.initialize();`;

const moduleRows = [
  ["Core", "Runtime, models, conversations, scheduling", "Available"],
  ["Capabilities", "Tools, skills, registry, enablement, policy", "Available"],
  ["Agents", "Neutral sessions and structured events", "Available"],
  ["Workflow", "Durable tasks, retries, execution history", "Evolving"],
  ["Knowledge", "Documents, embeddings, retrieval, access policy", "Planned"],
  ["Nexus", "Local service and device discovery/control", "Planned"],
];

export default function DocsPage() {
  return (
    <div className="docs-layout shell">
      <aside className="docs-nav" aria-label="Documentation sections">
        <span>DOCUMENTATION</span>
        <a href="#overview">Overview</a><a href="#getting-started">Getting started</a><a href="#architecture">Architecture</a><a href="#modules">Modules</a><a href="#status">Release status</a>
      </aside>
      <article className="docs-content">
        <header className="docs-hero" id="overview">
          <p className="eyebrow"><span className="pulse" /> DEVELOPER PREVIEW</p>
          <h1>Build with Omnix.</h1>
          <p>Omnix provides provider-neutral contracts for local intelligence in Flutter. It owns engine concerns while your application keeps its interface, product policy, persistence choices, and identity.</p>
        </header>

        <section className="docs-section" id="getting-started">
          <span className="kicker">01 / GETTING STARTED</span><h2>Install and initialize</h2>
          <p>Omnix is currently a developer preview and is not yet published to pub.dev. During development, consume it from a local path or Git. The declaration below represents the intended published API.</p>
          <pre><code>{install}</code></pre>
          <p>Provider integrations are opt-in entrypoints. The Flutter Gemma adapter composes the current inference and agent backends behind Omnix contracts.</p>
          <pre><code>{runtime}</code></pre>
        </section>

        <section className="docs-section" id="architecture">
          <span className="kicker">02 / ARCHITECTURE</span><h2>Stable contracts, replaceable internals</h2>
          <div className="docs-callout"><strong>Host application</strong><span>&#8594;</span><strong>Omnix API</strong><span>&#8594;</span><strong>Provider adapters</strong><span>&#8594;</span><strong>Model runtime</strong></div>
          <p>Public Dart contracts are handwritten and provider-neutral. Adapter packages translate those contracts to concrete runtimes. Rust sits behind the same boundary and replaces proven components only when the performance, portability, or security benefit is measurable.</p>
        </section>

        <section className="docs-section" id="modules">
          <span className="kicker">03 / MODULES</span><h2>Capability boundaries</h2>
          <p>Modules follow reusable engine responsibilities rather than copying the navigation of any host application.</p>
          <div className="module-table">
            {moduleRows.map(([name, responsibility, state]) => <div key={name}><strong>{name}</strong><span>{responsibility}</span><em>{state}</em></div>)}
          </div>
        </section>

        <section className="docs-section" id="status">
          <span className="kicker">04 / RELEASE STATUS</span><h2>What the preview means</h2>
          <p>Model installation, inference conversations, provider-neutral history, runtime scheduling, capability registration, and the Flutter Gemma agent adapter are implemented and tested. Portable skill loading, durable workflow execution, knowledge retrieval, and broader platform verification remain active milestones.</p>
          <div className="notice"><strong>Use it to evaluate and contribute.</strong><p>Do not treat the 0.1 developer API as frozen yet. Breaking changes will be documented before the first stable release.</p></div>
        </section>
      </article>
    </div>
  );
}
