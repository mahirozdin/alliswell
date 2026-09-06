/**
 * The page's shape, with none of its words (EE-153).
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
 */
export const SECTIONS = Object.freeze([
  { key: 'hero', component: 'EeHero' },
  { key: 'personas', component: 'PillarGrid', anchor: 'who' },
  { key: 'proof', component: 'StatStrip' },
  { key: 'portal', component: 'StepTimeline', anchor: 'portal' },

  // The service desk: one argument, then the screens that make it.
  { key: 'itsm', component: 'FeatureSection', anchor: 'itsm' },
  { key: 'itsmTabs', component: 'ShotTabs' },

  { key: 'sla', component: 'FeatureSection', anchor: 'sla' },
  { key: 'slaTabs', component: 'ShotTabs' },

  { key: 'org', component: 'FeatureSection', anchor: 'org' },
  { key: 'orgTabs', component: 'ShotTabs' },

  { key: 'identity', component: 'FeatureSection', anchor: 'identity' },
  { key: 'security', component: 'PillarGrid' },

  { key: 'meetings', component: 'FeatureSection', anchor: 'meetings' },
  { key: 'ops', component: 'SelfHostSection', anchor: 'ops' },
  { key: 'packages', component: 'ComparisonTable', anchor: 'packages' },
  { key: 'contact', component: 'ContactForm', anchor: 'contact' },
  { key: 'faq', component: 'FaqSection', anchor: 'faq' },
]);

/**
 * Which feature rows are flipped.
 *
 * `FeatureSection` takes `flip` from the parent rather than computing it from
 * an index, so the zig-zag survives a section being reordered — the homepage
 * learned that first. Here the feature rows are not adjacent (tabs sit between
 * them), so alternating on their own running index is what reads as a rhythm.
 */
export const FEATURE_KEYS = Object.freeze(
  SECTIONS.filter((s) => s.component === 'FeatureSection').map((s) => s.key),
);
