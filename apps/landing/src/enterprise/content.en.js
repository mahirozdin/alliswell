/**
 * Every word on the enterprise page, in English (EE-151).
 *
 * One file per language rather than `{en, tr}` beside every key: copy has to be
 * readable as prose to be reviewable as prose, which is the same reason
 * `src/content.js` gives for existing at all. What keeps the two honest is a
 * gate (`npm run check:copy`, EE-152) rather than a convention.
 *
 * ── WHAT THIS PAGE MAY CLAIM ──────────────────────────────────────────────
 *
 * The page it replaces went stale: it told readers for four epics that
 * directory integration was not included, while LDAP, SAML, OIDC and SCIM had
 * shipped. So the copy here is derived from the code, and four rules bind it:
 *
 *   • Packages describe what a team is SOLD, not a hard boundary around each
 *     feature. Six of the ten entitlement keys are declared and read by
 *     nothing; selling them as modules would be selling a promise nobody keeps.
 *   • Routing is service → unit → workspace: static, deterministic, and it
 *     refuses rather than guesses. It is not a rules engine and must never be
 *     written as one.
 *   • A screen a customer cannot open is not a feature. The team-wide audit
 *     screen exists in the source and in no router.
 *   • Numbers are the ones that were measured. "Tested at a million requests"
 *     is true; a millisecond figure is not, because the same query moved 23×
 *     between machines.
 *
 * Screenshot paths are stored WHOLE (`/shots/ee/...`), never composed, because
 * the CI gate greps the built bundle for those literals — a path assembled at
 * runtime is a path it cannot see.
 */

export const APP_URL = '/app';
export const REPO_URL = 'https://github.com/mahirozdin/alliswell';
export const CONTACT_EMAIL = 'info@bubiapps.com';

export default {
  lang: 'en',

  seo: {
    title: 'AllisWell Enterprise — service desk, units and SLAs on your own servers',
    description:
      'Teams, subdomains, permissions, units, ITSM with SLAs and service health, a public ' +
      'request portal and meeting-note AI — self-hosted, offline-first, on your own database.',
    ogImage: '/shots/og/enterprise-en.jpg',
  },

  nav: {
    home: '/',
    links: [
      { label: 'The service desk', href: '#itsm' },
      { label: 'SLAs', href: '#sla' },
      { label: 'Identity', href: '#identity' },
      { label: 'Packages', href: '#packages' },
    ],
    cta: { label: 'Talk to us', href: '#contact' },
    starsLabel: 'Star',
  },

  hero: {
    eyebrow: 'AllisWell Enterprise',
    title: 'A service desk your organisation runs, on your own servers',
    lede:
      'Teams, units and permissions. A service catalogue whose promises are measured on a ' +
      'business calendar rather than a wall clock. A public request form for the people who ' +
      'have no account and should not need one. Installed on your hardware, against your own ' +
      'database — and still working when the Wi-Fi on the shop floor is not.',
    primary: { label: 'Talk to us', href: '#contact' },
    secondary: { label: 'How it is installed', href: '#ops' },
    shot: '/shots/ee/hero-light-en.jpg',
    shotDark: '/shots/ee/hero-dark-en.jpg',
    alt:
      'Two screens side by side: a unit’s request queue with priorities and SLA states, and ' +
      'the SLA dashboard showing 76.2% of promises kept across 47 requests, broken down by ' +
      'desk and by service',
  },

  footer: {
    blurb:
      'AllisWell Enterprise adds teams, units, permissions, a service desk and SLAs to the ' +
      'AllisWell you can already run for free. Commercially licensed, installed on your own ' +
      'servers.',
    notes:
      'Not affiliated with Microsoft, Apple, Google, Anthropic or OpenAI. Product names are ' +
      'their owners’.',
    privacyLabel: 'Privacy',
    supportLabel: 'Support',
    columns: [
      {
        title: 'Enterprise',
        links: [
          { label: 'The service desk', href: '#itsm' },
          { label: 'SLAs and service health', href: '#sla' },
          { label: 'The public request portal', href: '#portal' },
          { label: 'Identity and security', href: '#identity' },
          { label: 'Packages', href: '#packages' },
          { label: 'Talk to us', href: '#contact' },
        ],
      },
      {
        title: 'Run it yourself',
        links: [
          { label: 'Self-hosting guide', href: `${REPO_URL}/blob/main/docs/SELF-HOSTING.md` },
          { label: 'Architecture', href: `${REPO_URL}/blob/main/docs/ARCHITECTURE.md` },
          { label: 'REST API reference', href: '/docs/api' },
          { label: 'Security policy', href: `${REPO_URL}/blob/main/SECURITY.md` },
        ],
      },
      {
        title: 'The free edition',
        links: [
          { label: 'alliswell.space', href: '/' },
          { label: 'Open the app', href: APP_URL },
          { label: 'Source on GitHub', href: REPO_URL },
          { label: 'Licence (PolyForm NC)', href: `${REPO_URL}/blob/main/LICENSE` },
        ],
      },
    ],
  },

  /** The JavaScript-off block inside `#app`, kept in step with the entry HTML. */
  fallback: {
    contact: 'Write to',
    other: 'Türkçe',
    home: 'alliswell.space',
  },
};
