import type { Metadata } from "next";
import Link from "next/link";
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
    default: "Omnix | On-device intelligence engine",
    template: "%s | Omnix",
  },
  description:
    "An open, headless, on-device intelligence engine for Flutter applications.",
  metadataBase: new URL("https://omnix.omniecosystem.xyz"),
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>
        <a className="skip-link" href="#main-content">Skip to content</a>
        <header className="site-header">
          <div className="shell nav-shell">
            <Link className="brand" href="/" aria-label="Omnix home">
              <span className="brand-mark" aria-hidden="true"><span /></span>
              <span className="wordmark">omni<span>x</span></span>
            </Link>
            <nav aria-label="Main navigation">
              <Link href="/docs">Docs</Link>
              <Link href="/#architecture">Architecture</Link>
              <Link href="/#modules">Modules</Link>
              <a href="https://github.com/omniecosystem/omnix">GitHub</a>
            </nav>
            <a className="header-cta" href="https://github.com/omniecosystem/omnix">
              View source <span aria-hidden="true">&#8599;</span>
            </a>
          </div>
        </header>
        <main id="main-content">{children}</main>
        <footer className="site-footer">
          <div className="shell footer-grid">
            <div>
              <Link className="brand footer-brand" href="/">
                <span className="brand-mark small" aria-hidden="true"><span /></span>
                <span className="wordmark">omni<span>x</span></span>
              </Link>
              <p>Open infrastructure for private, on-device intelligence.</p>
            </div>
            <div className="footer-links">
              <div><strong>Build</strong><Link href="/docs">Documentation</Link><a href="https://github.com/omniecosystem/omnix">Source</a></div>
              <div><strong>Ecosystem</strong><a href="https://omniecosystem.xyz">Omni Ecosystem</a><a href="https://omnies.omniecosystem.xyz">Omnies</a></div>
            </div>
          </div>
          <div className="shell footer-bottom"><span>&copy; 2026 Omni Ecosystem</span><span>Apache 2.0</span></div>
        </footer>
      </body>
    </html>
  );
}
