/**
 * The page's shape, with none of its words (EE-153; reordered in EE-164 and
 * OPH-388, shortened to one argument in OPH-413).
 *
 * Order, anchors and which component renders each section. Nothing here is
 * translatable, which is the point: `check:copy` compares two content modules
 * key for key, and it can only do that if the STRUCTURE is not one of the
 * things that can differ between them. Moving a section is a line here; the
 * copy does not move with it.
 *
 * `key` is the property each section reads out of the content module. A section
 * whose key is absent from the content is a section that does not render — so
 * this list can carry a row before its copy exists, and `check:copy` still
 * refuses a row whose copy exists in one language only.
 *
 * ── THE ORDER IS ONE ARGUMENT (OPH-413) ────────────────────────────────────
 *
 * Problem → solution → proof → pilot → demo request (owner-approved plan,
 * 2026-11-07, landing-audit K9). The page used to walk the 18-slide sales
 * deck one slide per section: 27 sections, 26 000 px on a desktop and 39 000
 * on a phone. The deck is still one click away as a PDF; the page argues once.
 *
 *   1. the promise (hero), then the reader's own Monday morning (problem: the
 *      phone call nobody wrote down);
 *   2. the solution: one request's road as a record (journey, six steps), then
 *      the screens in one tabbed tour — the list, one request, the rules, the
 *      SLA board, the company portal — instead of a section per screen;
 *   3. the proof a buyer can check: offline, KVKK, our installation and
 *      migration, and source the IT team can read;
 *   4. the pilot: one unit, a few weeks, measured; where it runs, the cloud
 *      packages and the deck to pass on;
 *   5. the questions, then the demo request — the last thing on the page.
 *
 * `proof` holds the `integrity` card `check-copy` ties to capabilities.js.
 */
export const SECTIONS = Object.freeze([
  { key: 'hero', component: 'EeHero' },
  // Problem.
  { key: 'problem', component: 'ProblemGrid', anchor: 'problem' },
  // Solution.
  { key: 'journey', component: 'JourneyFlow', anchor: 'journey' },
  { key: 'tour', component: 'ShotTabs', anchor: 'tour' },
  // Proof.
  { key: 'proof', component: 'PillarGrid', anchor: 'proof' },
  // Pilot, and how you get it.
  { key: 'pilot', component: 'JourneyFlow', anchor: 'pilot' },
  { key: 'deploy', component: 'DeployOptions', anchor: 'deploy' },
  { key: 'packages', component: 'ComparisonTable', anchor: 'packages' },
  { key: 'deck', component: 'DeckDownload', anchor: 'deck' },
  // The demo request, after the questions it answers.
  { key: 'faq', component: 'FaqSection', anchor: 'faq' },
  { key: 'contact', component: 'ContactForm', anchor: 'contact' },
]);

/**
 * The components that lay copy beside a picture and therefore take part in the
 * zig-zag (one running count, so neighbours mirror each other). Since OPH-413
 * the tour is the only one.
 */
export const TWO_COLUMN_COMPONENTS = Object.freeze(['ShotTabs']);
