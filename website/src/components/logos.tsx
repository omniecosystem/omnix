import styles from "./logos.module.css";

const cyan = "#00ffff";
const loopPath = "M110 150C110 120 135 120 150 150C165 180 190 180 190 150C190 120 165 120 150 150C135 180 110 180 110 150";
type LogoProps = { className?: string; label?: string };

// Same source geometry as the ecosystem's original SVGs. A few stroked paths
// replace dozens of individually filtered particles; no client component needed.
function OmniLoop() {
  return <g fill="none" stroke={cyan} strokeLinecap="round" strokeLinejoin="round">
    <path d={loopPath} strokeWidth="5" opacity=".25" />
    {[{ length: 70, opacity: .12 }, { length: 35, opacity: .28 }, { length: 12, opacity: .6 }, { length: 1, opacity: 1 }].map(({ length, opacity }) =>
      <path key={length} className={styles.loopTrail} d={loopPath} pathLength="100" strokeWidth="5" strokeDasharray={`${length} ${100 - length}`} opacity={opacity} />)}
  </g>;
}

export function OmniAskLogo({ className = "", label = "OmniAsk logo" }: LogoProps) {
  return <svg className={`${styles.logo} ${className}`} viewBox="0 0 300 300" role="img" aria-label={label}>
    <path d="M150 67.5C100.3 67.5 67.5 100.3 67.5 150c0 44.06 28.13 74.53 65.63 81.56l16.88 23.44 16.88-23.44c37.5-7.03 65.63-37.5 65.63-81.56c0-49.69-32.81-82.5-82.5-82.5z" fill="none" stroke={cyan} strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" />
    <OmniLoop />
  </svg>;
}

export function OmnixLogo({ className = "", label = "Omnix logo" }: LogoProps) {
  return <svg className={`${styles.logo} ${className}`} viewBox="0 0 300 300" role="img" aria-label={label}>
    <g fill="none" stroke={cyan} strokeWidth="5">
      <ellipse className={styles.orbitForward} cx="150" cy="150" rx="123" ry="83" opacity=".28" />
      <ellipse className={styles.orbitReverse} cx="150" cy="150" rx="123" ry="83" opacity=".32" />
    </g>
    <OmniLoop />
  </svg>;
}

export function OmniesLogo({ className = "", label = "Omnies logo" }: LogoProps) {
  return <svg className={`${styles.logo} ${className}`} viewBox="0 0 300 300" role="img" aria-label={label}>
    <OmniLoop />
    <g className={styles.sparkOrbit}>
      {Array.from({ length: 8 }, (_, index) => {
        const angle = index * Math.PI / 4;
        const x = (150 + 92 * Math.sin(angle)).toFixed(4);
        const y = (150 - 92 * Math.cos(angle)).toFixed(4);
        return <g key={index} transform={`translate(${x} ${y})`}>
          <g className={styles.sparkFrame}><path className={styles.spark} style={{ animationDelay: `${-index * .36}s` }} d="M0 -18 L6 -6 L18 0 L6 6 L0 18 L-6 6 L-18 0 L-6 -6 Z" stroke={cyan} strokeWidth="5" fill="none" strokeLinecap="round" strokeLinejoin="round" /></g>
        </g>;
      })}
    </g>
  </svg>;
}

function knotRuns(under: boolean): string {
  let path = "", inRun = false;
  for (let index = 0; index <= 500; index++) {
    const t = index / 500 * Math.PI * 2;
    const matches = under ? Math.sin(6 * t) < 0 : Math.sin(6 * t) >= 0;
    if (matches) {
      const x = 150 + 80 * Math.cos(t) - 25 * Math.cos(7 * t);
      const y = 150 + 80 * Math.sin(t) - 25 * Math.sin(7 * t);
      path += `${inRun ? "L" : "M"} ${x.toFixed(2)} ${y.toFixed(2)} `;
    }
    inRun = matches;
  }
  return path;
}
const underRuns = knotRuns(true), overRuns = knotRuns(false);

export function OmnixusLogo({ className = "", label = "Omnixus logo" }: LogoProps) {
  return <svg className={`${styles.logo} ${className}`} viewBox="0 0 300 300" role="img" aria-label={label}>
    <OmniLoop />
    <g className={styles.knotOrbit} fill="none" strokeLinecap="round" strokeLinejoin="round">
      <path d={underRuns + overRuns} stroke="#101820" strokeWidth="5" />
      <path d={underRuns + overRuns} stroke={cyan} strokeWidth="5" opacity=".26" />
      <path className={styles.knotUnder} d={underRuns} stroke={cyan} strokeWidth="2.6" strokeDasharray="10 120" />
      <path className={styles.knotOver} d={overRuns} stroke={cyan} strokeWidth="2.6" strokeDasharray="10 120" />
    </g>
  </svg>;
}

export function OmniMark({ className = "", label = "Omni logo" }: LogoProps) {
  return <svg className={`${styles.logo} ${className}`} viewBox="104 115 92 70" role="img" aria-label={label}>
    <OmniLoop />
  </svg>;
}
