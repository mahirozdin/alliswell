/* global __AW_PROOF__ */
/**
 * OPH-412 (landing-audit K2): the honest proof line under the hero. The
 * release count and the stars are read from the GitHub API when the site is
 * built (`scripts/proof.js`, handed in by vite.config.js as `__AW_PROOF__`),
 * never typed into the copy. Without the API the line is the fixed text, with
 * no number in it: a number nobody counted is not proof.
 */

/** What the build counted, or null (no API, or read outside a Vite build). */
export const BUILD_PROOF = typeof __AW_PROOF__ === 'undefined' ? null : __AW_PROOF__;

/** Stars are shown only once they say something (owner's taste, landing-audit K2). */
const STARS_SHOWN_FROM = 100;

/** "July 2026" / "Temmuz 2026" for a `YYYY-MM`. */
function monthOf(first, lang) {
  const [year, month] = first.split('-').map(Number);
  return new Intl.DateTimeFormat(lang, { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(
    new Date(Date.UTC(year, month - 1, 15)),
  );
}

/**
 * The parts of the proof line, in order, joined with a middle dot by the page.
 * @param {{ source: {label: string}, releases: string, free: string }} copy
 * @param {{ releases?: number, first?: string } | null} proof
 * @param {string} lang
 */
export function proofParts(copy, proof, lang) {
  const parts = [copy.source.label];
  if (proof?.releases && proof.first) {
    parts.push(copy.releases.replace('{n}', String(proof.releases)).replace('{month}', monthOf(proof.first, lang)));
  }
  parts.push(copy.free);
  return parts;
}

/** The star count for the nav's GitHub button, or null below the threshold. */
export function starsLabel(proof, lang) {
  const stars = proof?.stars;
  if (typeof stars !== 'number' || stars < STARS_SHOWN_FROM) return null;
  return new Intl.NumberFormat(lang).format(stars);
}
