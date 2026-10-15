import Link from "next/link";
import { OmniMark, OmniesLogo, OmnixLogo, OmnixusLogo } from "./logos";
import styles from "./brand.module.css";

const brands = {
  Omni: { slogan: "From AI to EI", Logo: OmniMark },
  Omnix: { slogan: "Cognitive System", Logo: OmnixLogo },
  Omnies: { slogan: "Cognitive Agents", Logo: OmniesLogo },
  Omnixus: { slogan: "Cognitive Ecosystem", Logo: OmnixusLogo },
} as const;

export function Brand({ name, className = "" }: { name: keyof typeof brands; className?: string }) {
  const { slogan, Logo } = brands[name];
  return <Link className={`${styles.brand} ${className}`} href="/" aria-label={`${name}${slogan ? ` — ${slogan}` : ""} home`}>
    <span className={styles.symbol} aria-hidden="true"><Logo /></span>
    <span className={styles.lockup}>
      <span className={styles.name}>{name}</span>
      {slogan && <svg className={styles.tagline} viewBox="0 0 100 14" preserveAspectRatio="none" aria-hidden="true">
        <text x="0" y="11" textLength="100" lengthAdjust="spacingAndGlyphs">{slogan}</text>
      </svg>}
    </span>
  </Link>;
}
