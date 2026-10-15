import type { Metadata } from "next";
import Link from "next/link";
import { Brand } from "@/components/brand";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: {
    default: "Omnix | Cognitive System",
    template: "%s | Omnix",
  },
  description:
    "An open, headless, Rust-first Cognitive System with modular native capabilities and Dart APIs.",
  metadataBase: new URL("https://omnix.omniecosystem.xyz"),
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>
        <a className="skip-link" href="#main-content">Skip to content</a>
        <header className="site-header">
          <div className="shell nav-shell">
            <Brand name="Omnix" />
            <nav aria-label="Main navigation">
              <Link href="/docs">Docs</Link>
              <Link href="/#architecture">Architecture</Link>
              <Link href="/#modules">Modules</Link>
              <a href="https://github.com/omniecosystem/omnix" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">GitHub</a>
            </nav>
            <a className="header-cta" href="https://github.com/omniecosystem/omnix" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">
              View source <span aria-hidden="true">&#8599;</span>
            </a>
          </div>
        </header>
        <main id="main-content">{children}</main>
        <footer className="site-footer">
          <div className="shell footer-grid">
            <div>
              <Brand name="Omnix" className="footer-brand" />
              <p>Open infrastructure for private, on-device Cognitive Systems.</p>
            </div>
            <div className="footer-links">
              <div><strong>Build</strong><Link href="/docs">Documentation</Link><a href="https://github.com/omniecosystem/omnix" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Source</a></div>
              <div><strong>Ecosystem</strong><a href="https://omniecosystem.xyz" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Omni Ecosystem</a><a href="https://omnies.omniecosystem.xyz" target="_blank" rel="noopener noreferrer" title="Opens in a new tab">Omnies</a></div>
            </div>
          </div>
          <div className="shell footer-bottom"><span>&copy; 2026 Omni Ecosystem</span><span>Apache 2.0</span></div>
        </footer>
      </body>
    </html>
  );
}
