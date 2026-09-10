/**
 * The page's shape, with none of its words (EE-153; reordered in EE-164).
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
 * ── THE ORDER IS THE SALES CONVERSATION (EE-164) ──────────────────────────
 *
 * Who it is for → the request desk → the promise (SLA) → the outside world
 * (customers, dealers) → the organisation and who may do what → the daily work
 * the whole company does in the same place → identity and security → meetings
 * → HOW you get it (cloud or on-premise) → what the cloud packages are → the
 * form → the questions. The proof strip of technical numbers that used to sit
 * under the hero is gone: none of its figures changed a buyer's decision.
 */
export const SECTIONS = Object.freeze([
  { key: 'hero', component: 'EeHero' },
  { key: 'personas', component: 'PillarGrid', anchor: 'who' },

  // Request management: one argument, then the screens that make it.
  { key: 'itsm', component: 'FeatureSection', anchor: 'itsm' },
  { key: 'itsmTabs', component: 'ShotTabs' },

  { key: 'sla', component: 'FeatureSection', anchor: 'sla' },
  { key: 'slaTabs', component: 'ShotTabs' },

  { key: 'portal', component: 'StepTimeline', anchor: 'portal' },

  { key: 'org', component: 'FeatureSection', anchor: 'org' },
  { key: 'orgTabs', component: 'ShotTabs' },

  // The core product — tasks, board, projects, notes, files — is part of what
  // an enterprise buys, and the page did not mention it once before EE-164.
  { key: 'workspace', component: 'FeatureSection', anchor: 'work' },
  { key: 'workspaceTabs', component: 'ShotTabs' },

  { key: 'identity', component: 'FeatureSection', anchor: 'identity' },
  { key: 'security', component: 'PillarGrid' },

  { key: 'meetings', component: 'FeatureSection', anchor: 'meetings' },

  // Cloud or on-premise. Replaces the "install it yourself" terminal block:
  // an enterprise customer never installs this product — we do.
  { key: 'deploy', component: 'DeployOptions', anchor: 'deploy' },
  { key: 'packages', component: 'ComparisonTable', anchor: 'packages' },
  { key: 'contact', component: 'ContactForm', anchor: 'contact' },
  { key: 'faq', component: 'FaqSection', anchor: 'faq' },
]);

/**
 * The components that lay copy beside a picture, and therefore take part in
 * the zig-zag. `FeatureSection` and `ShotTabs` alternate on ONE running count
 * rather than each on its own, so a feature row and the tab block that follows
 * it mirror each other — copy left, then copy right — instead of two rows in
 * a row with the copy on the same side.
 */
export const TWO_COLUMN_COMPONENTS = Object.freeze(['FeatureSection', 'ShotTabs']);
