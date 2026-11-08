# ADR-0065 — The enterprise page is rendered on the server and argues once

- **Status:** Accepted
- **Date:** 2026-11-08
- **Related task:** OPH-413 (Epic 35, landing-audit K3, K8, K9; persona E-15)

## Context

ADR-0061 put the homepage through a build-time render and left the enterprise pages as written in
ADR-0036: Vue mounting into an empty container. The audit
([landing-audit](../research/2026-11-design-ux/landing-audit.md) K8, K9) measured what that costs.
The HTML held one heading and an address; a crawler, a link preview or a reader without scripts
saw nothing else. The page followed the 18-slide sales deck one slide per section: 27 sections,
26 474 px on a desktop, 39 043 on a phone. Every section began at opacity 0 and waited for an
IntersectionObserver, so a full-page capture, print, reader mode and a fast scroll showed blank
space where content was (E-15). The English page showed the Turkish sample factory's records.

The owner approved the order problem → solution → proof → pilot → demo request (plan,
2026-11-07).

## Decision

1. **Rendered on the server.** The four Vue pages share one server entry, `src/entry-server.js`,
   with a render function per page (`home`, `enterprise`); `scripts/routes.js` names each page's
   `page` and marks all four `ssr`. `vite build --ssr src/entry-server.js` builds it,
   `scripts/prerender.mjs` writes every page and refuses a build whose HTML lacks a section's
   heading, the dev middleware serves the same render, and `src/enterprise/main.{en,tr}.js`
   hydrate with `createSSRApp`. The entries carry `<!--ssr-head-->` and `<!--ssr-outlet-->` like
   the homepage's. Amends ADR-0061 decision 3 and ADR-0036 for the enterprise entries.
2. **Nothing starts invisible.** The `v-reveal` directive and its CSS are removed. Content is
   visible from the first paint; `check:pages` fails a built enterprise page that still carries a
   reveal class or lacks a section, in order.
3. **One argument.** `src/enterprise/page.js` holds eleven sections: hero, problem, journey, a
   tabbed tour of the screens (`ShotTabs`), proof, pilot, deployment, cloud packages, the deck,
   questions, and the contact form last. The deck stays one click away as a PDF. Proof says only
   what a buyer can check today: offline, KVKK, our installation and migration, readable source.
4. **Each language shows its own data.** The tour and the English hero use the app's captures in
   `screenshots/ee/` (`-en` holds English sample records); the sales set keeps only the Turkish
   hero, the deck covers and the English hero the store script composes.

## Alternatives considered

- **Prerender only the text, keep client mounting.** Two renderings of one page drift; the
  homepage already has the machinery.
- **Keep the reveal and fall back with `<noscript>` CSS.** It fixes scripting-off, not print,
  capture, reader mode or a fast scroll, which all run scripts.
- **Tabs per deck group (three clusters).** Still four long sections of annotated captures; the
  ≤ 12 000 px target was out of reach without dropping the run.

## Consequences

- Desktop 10 715 px, phone 15 074 px (headless Chrome, 1440 and 390 wide).
- `check:home` reads `HOME_PAGES`; the enterprise pages are held by `check:pages`, `check:copy`
  (now `ssr`) and `apps/api/test/unit/landing-enterprise.test.js`, which renders the pages
  through Vite.
- Old anchors (`#itsm`, `#sla`, `#intake`, …) no longer exist; links to them land on the page top.
- Annotated per-screen sections (`AnnotatedShots`, `StatusFlow`, `ChannelList`, `GroupHeading`,
  `FeatureSection`) are gone; the presentation carries that depth.
