/**
 * The page's shape, with none of its words (EE-153; reordered in EE-164, and
 * again in OPH-388 to follow the sales deck).
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
 * ── THE ORDER IS THE SALES CONVERSATION — THE DECK'S (OPH-388) ────────────
 *
 * The page follows the 18-slide factory deck that is sent to buyers, so a
 * reader who saw one recognises the other. The reader is a factory's general
 * manager, IT manager, maintenance or after-sales manager.
 *
 *   1. the promise (hero), then the reader's own Monday morning (problem: the
 *      phone call nobody wrote down) and what one request's road looks like
 *      when it is a record (journey, six steps);
 *   2. the steps one by one, in the order they happen: the organisation and
 *      roles, the service catalogue, the rules that route a request, the unit's
 *      request list, one request's whole story, approvals / changes / known
 *      errors, the machine a request is about;
 *   3. the promise kept: SLA, then the SLA board and performance;
 *   4. people: their own list, absences and on-call; the states, and what the
 *      requester sees of them;
 *   5. outside: the four ways in, the company portal and the tracking link;
 *   6. "on the shop floor, on your rules and your data" — offline, KVKK,
 *      installation and migration by us, a pilot with one unit;
 *   7. "also" — what the deck does not show but a buyer still buys: the daily
 *      work, identity, meeting notes; then cloud or own server, the cloud
 *      packages, the deck as a PDF, the form, the questions.
 *
 * `security` keeps its key (and its anchor `#factory`) because `check-copy`
 * holds its `integrity` card to capabilities.js; `itsm` keeps its key for the
 * same reason (`itsm.points` carries the offline sentence).
 */
export const SECTIONS = Object.freeze([
  { key: 'hero', component: 'EeHero' },
  { key: 'problem', component: 'ProblemGrid', anchor: 'problem' },
  { key: 'journey', component: 'JourneyFlow', anchor: 'journey' },

  // Setting it up: the organisation, the catalogue, the rules.
  { key: 'org', component: 'AnnotatedShots', anchor: 'admin' },
  { key: 'catalog', component: 'AnnotatedShots', anchor: 'catalog' },
  { key: 'rules', component: 'AnnotatedShots', anchor: 'rules' },

  // Request management (ITSM): the list, the request, the hard cases, the machine.
  { key: 'itsm', component: 'AnnotatedShots', anchor: 'itsm' },
  { key: 'ticket', component: 'AnnotatedShots', anchor: 'request' },
  { key: 'approvals', component: 'AnnotatedShots', anchor: 'approvals' },
  { key: 'assets', component: 'AnnotatedShots', anchor: 'assets' },

  // The promise and whether it was kept.
  { key: 'sla', component: 'AnnotatedShots', anchor: 'sla' },
  { key: 'slaReport', component: 'AnnotatedShots', anchor: 'sla-report' },

  // People and the states a request moves through.
  { key: 'people', component: 'AnnotatedShots', anchor: 'people' },
  { key: 'statuses', component: 'StatusFlow', anchor: 'statuses' },

  // From outside: customers, dealers, suppliers.
  { key: 'intake', component: 'ChannelList', anchor: 'intake' },
  { key: 'portal', component: 'AnnotatedShots', anchor: 'portal' },

  // The deck's closing argument.
  { key: 'security', component: 'PillarGrid', anchor: 'factory' },

  // "Also": kept, shortened, after the factory story.
  { key: 'extras', component: 'GroupHeading', anchor: 'also' },
  { key: 'workspace', component: 'FeatureSection', anchor: 'work' },
  { key: 'workspaceTabs', component: 'ShotTabs' },
  { key: 'identity', component: 'FeatureSection', anchor: 'identity' },
  { key: 'meetings', component: 'FeatureSection', anchor: 'meetings' },

  // How you get it, and the way to ask.
  { key: 'deploy', component: 'DeployOptions', anchor: 'deploy' },
  { key: 'packages', component: 'ComparisonTable', anchor: 'packages' },
  { key: 'deck', component: 'DeckDownload', anchor: 'deck' },
  { key: 'contact', component: 'ContactForm', anchor: 'contact' },
  { key: 'faq', component: 'FaqSection', anchor: 'faq' },
]);

/**
 * The components that lay copy beside a picture, and therefore take part in
 * the zig-zag. They alternate on ONE running count rather than each on its
 * own, so consecutive two-column sections mirror each other — copy left, then
 * copy right — instead of two rows in a row with the copy on the same side.
 * `AnnotatedShots` counts only when it is side by side (`layout: 'side'`, or
 * `'phones'` with a list): a grid or a lone row of phones has no side to swap,
 * and counting it would put two neighbours' copy on the same side.
 */
export const TWO_COLUMN_COMPONENTS = Object.freeze(['FeatureSection', 'ShotTabs', 'AnnotatedShots']);
