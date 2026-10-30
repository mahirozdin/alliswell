# ADR-0061 — The marketing homepage wears Hallmark Dusk, renders on the server, and shows the product in loops

- **Status:** Accepted
- **Date:** 2026-10-30
- **Related task:** OPH-389 (the homepage and README rebuild the owner asked for on 2026-10-30)
- **Amends:** [ADR-0036](0036-landing-multi-entry-enterprise-page.md) (the homepage, one of its Vite
  entries, now renders on the server and hydrates; the enterprise entries are unchanged)
- **Scoped exception to:** [ADR-0005](0005-alliswell-glass-design-system.md) /
  [ADR-0012](0012-liquid-glass-v2-visual-refresh.md) and AGENTS I-11 (DESIGN.md G7, G8, §3.3), for `/` and `/tr` only

## Context

The homepage was the old Glass page rendered in the browser: the HTML that reached a crawler,
a link preview or a reader without scripting held one heading and a sentence saying the page
needed JavaScript. It explained the product in eleven text-heavy sections, showed no motion
anywhere, and its Turkish was a translation of the English. The owner reviewed showcase READMEs
and comparable product pages (claude-seo, ruflo; AFFiNE, Plane, Twenty, Super Productivity, Amie,
Todoist, TickTick and others) and asked for the page to be rebuilt from scratch with the Dusk
theme of the Hallmark design skill (github.com/nutlope/hallmark), with the product shown in
animation and film, the copy rewritten in both languages, and the enterprise page left alone.

## Decision

1. **Look.** `/` and `/tr` follow Hallmark's Dusk theme: a real dusk photograph behind the hero
   (Wikimedia Commons, CC BY 3.0, credited in the footer), slate paper below it, the product in
   smoked glass with a lit edge, bone wells for the one light surface, periwinkle and apricot as
   the only two signals, Wix Madefor Display and Text. Tokens live in
   `apps/landing/src/home/styles/tokens.css` (Hallmark's scaffold); no colour, font or spacing
   literal past it (`check:home`). Hallmark's floor holds: no eyebrows, no emoji icons, no em or
   en dashes in copy, about 450 visible words (`check:copy`), and `sloplint --render` with zero
   FAIL before a homepage change ships.
2. **Scoped exceptions to AllisWell Glass, homepage only.** Dark only, no theme switch (G7: the
   one theme is checked, contrast at 4.5:1 / 3:1 measured by sloplint's render tier). Web fonts,
   self-hosted from `public/fonts/` under the SIL OFL, never fetched from a font CDN (§3.3).
   Motion past G8: muted product loops, a 48-second photograph drift and a one-minute film, each
   with a reduced-motion fallback (posters only) and a pause control on every loop (WCAG 2.2.2).
   The app, the enterprise page and the markdown pages keep Glass unchanged.
3. **Rendered on the server.** The homepage is Vue rendered at build time
   (`vite build --ssr src/home/entry-server.js`, then `scripts/prerender.mjs`) and hydrated by
   `src/home/main.{en,tr}.js`; dev serves the same render through `scripts/home-ssr.js`. Every
   section reads with scripting off; JavaScript adds the tour's tabs, the loops' playback, the
   copy button and the bar's glass. The enterprise entries still mount into an empty container
   (ADR-0036 as written).
4. **Isolation.** The homepage lives in `src/home/` with its own components and stylesheet;
   the enterprise page keeps `style.css` and the shared components. ESLint fences the imports
   both ways; `check:home` fails if either page's CSS carries the other's tokens. Shared
   constants moved to `src/site.js`.
5. **Media pipeline.** Loops and the film are HyperFrames compositions in
   `media/hyperframes/compositions/` (sources committed; renders, the music file and copied
   screenshots gitignored), built from the real screenshots. `npm run media:promote` encodes
   them (H.264, faststart, silent loops, AAC film) with AVIF/JPEG posters, names every file after
   the sha256 of its bytes under `apps/landing/public/media/`, writes `src/home/media.json` and
   prunes what it no longer names; README animations go to `docs/assets/readme/`. Budgets
   (`scripts/media-budgets.js`): a loop ≤ 1.5 MB, a film ≤ 12 MB, everything under
   `public/media` ≤ 30 MB, a README animation ≤ 3 MB. `check:media` holds manifest, files,
   hashes, budgets, MP4 structure and the photo credit, inside `landing:build` as well as CI,
   because the deploy builds without the CI checks. Hashed names let `.htaccess` cache video as
   immutable. The film's music is composed by `media/hyperframes/scripts/music.py`, so the
   project owns it outright.

## Alternatives considered

- **A static HTML template instead of Vue SSR.** Less client JavaScript, but markup in template
  literals, hand escaping, no template lint and a second authoring style in a repo whose
  marketing surface is Vue. SSR keeps one model and adds one build pass.
- **Reskinning the enterprise page too.** Declined by the owner: it shipped two days earlier
  from the sales deck and has its own reviewers.
- **A light variant of Dusk.** Dusk's character is the dark slate and the photograph; a second
  mode doubles the checks for a page with one job.
- **Video on a third-party host.** Embeds bring trackers and a player's chrome; the files are
  small enough to serve from the docroot, lazily, with immutable caching.
- **Licensed stock music.** The open catalogues were unreachable from the build machine, and a
  generated bed avoids a licence obligation altogether.

## Consequences

- A crawler, a link preview and a reader without scripting get the whole page in both languages.
- About 30 MB of media enters the history now, and every re-render that changes a file adds its
  new bytes; only approved finals are promoted. The verify sandbox excludes `media/` and
  `public/media/` unless `landing-build` asks for them.
- The site is behind Cloudflare's CDN, whose terms limit serving video at volume. Loops load only
  when they scroll into view and the total stays inside the budget; if traffic makes it matter,
  the film moves to R2 or Stream (an owner decision).
- Changing homepage copy now runs through Hallmark's floor in `check:copy`, and a change to the
  look should run `sloplint --render` against `vite preview` (docs/SCREENSHOTS.md, "Homepage media").
- DESIGN.md points here for the homepage; I-11 stays the rule everywhere else.
