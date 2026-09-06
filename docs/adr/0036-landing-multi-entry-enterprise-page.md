# ADR-0036 — The enterprise page is a Vite entry, not generated markdown

- **Status:** Accepted
- **Date:** 2026-09-06
- **Related task:** EE-142 (gate for EE-143 … EE-154)
- **Related:** [ADR-0005](0005-alliswell-glass-design-system.md) (the tokens both pages share),
  [ADR-0035](0035-api-docs-are-generated.md) (the other page that joined
  `STATIC_PAGES` and stays there)

## Context

`/enterprise` and `/enterprise/tr` are generated from `docs/ENTERPRISE.md` and
its Turkish twin by `apps/landing/scripts/static-pages.js`. That file's own
header states why, and names three properties it wanted: the page must be
indexable, it must read with JavaScript off, and it must exist in Turkish. The
Vue site has no i18n layer, so a second markdown source at a second route was
the only route to a Turkish page.

Every one of those three reasons was right, and two of them still are. What has
not held up is the *shape*.
The generated pages share one stylesheet family with the privacy policy, and
`enterprise.css` layers over it — a wider column, a coloured rule under each
`h2`, a figure style. It is a good document. It is still a document, and it is
read by someone deciding whether to put their company's service desk on our
software. The page has no hero, no alternating feature rows, no step-by-step
walkthrough of the flow it is selling, no package comparison, and no way to
start a conversation other than a `mailto:` at the bottom.

There is a second problem, and it is the more expensive one. **The page went
stale about its own product and nothing anywhere said so.** It still tells
readers that a capability is absent which has since shipped. The CI gate that
guards this page asserts that the markdown file exists and is linked from three
places — not that a word of it is still true. That is this repository's own
recurring lesson wearing a new hat: what a gate does not measure reads exactly
like the green it prints for what it does.

Markdown is not the cause of the staleness. But a marketing page assembled from
components, whose copy lives in a checked module beside the screenshots it
refers to, is a page whose drift has somewhere to be caught. A single
1 200-word document is not.

## Decision

**`/enterprise` and `/enterprise/tr` become their own Vite HTML entries, each
mounting a Vue application, and leave `STATIC_PAGES`.**

Three parts:

1. **Two hand-written HTML entries** (`enterprise/index.html`,
   `enterprise/tr/index.html`) carrying a complete `<head>` — title,
   description, canonical, the `hreflang` pair plus `x-default`, Open Graph
   including a real `og:image`, JSON-LD, theme colour, favicon. Vite mirrors an
   entry's source path into `dist/`, so these become real directories in the
   Apache docroot exactly as the generated pages were.
2. **Locale is chosen at build time by which entry loaded.** Each entry imports
   one content module. Rollup keeps the other language out of the chunk: no
   runtime detection, no flash of the wrong language, and a Turkish reader
   downloads Turkish.
3. **One route list.** `apps/landing/scripts/routes.js` exports the pages that
   are Vite entries and the union of every indexable page in the docroot,
   whatever produced it. The build, the dev-server middleware, the sitemap and
   the CI gates all read that one list. This is the direct answer to
   `static-pages.js`'s own warning that a gate carrying a hand-typed copy of the
   route list is a gate that goes blind the first time a page arrives by a new
   mechanism — which is precisely what this ADR does.

**`docs/ENTERPRISE.md` and its twin are reduced, not deleted.** Three sentences
of definition, the licensing section kept verbatim, and a link to the page.
Deleting them would break two README links, a SELF-HOSTING link, every external
link, and `rewriteLink()`'s fallback for unknown `.md` references. Keeping them
whole would duplicate the page's copy in a second place, which is the drift this
repository has paid for repeatedly. The split is a real audience split: someone
evaluating the licence on GitHub, next to `LICENSE` and
[ADR-0024](0024-license-polyform-noncommercial.md), is not the person on a sales
page.

### The JavaScript question, answered rather than waved past

Of the three properties, two are kept outright. **Indexable:** the entire
`<head>` is static HTML, so canonical, `hreflang`, Open Graph and JSON-LD are
readable without executing anything. **Turkish:** two entries, two content
modules, a parity gate.

The third changes, and the honest form of the change is this: **the JS-off
requirement was never a site-wide principle — it is load-bearing in exactly two
places, and both keep their mechanism.** The legal pages are fetched by App
Store and Play reviewers and by automated validators; the request portal is
opened by strangers on networks we do not control and serves a page whose CSP
forbids script outright. Neither moves. Meanwhile the site's own homepage has
required JavaScript since it was written; an enterprise page that does the same
is consistent with the site, not a regression from it.

Even so, each entry ships a real JavaScript-off rendering inside `#app`: a
heading, the page's one load-bearing claim, and a contact route. Vue's `mount()`
clears the container before its first render, so this is a rendering and not a
placeholder that flashes — and it is what the CI `<h1>` assertion reads.

## Alternatives considered

**Keep the markdown and grow `enterprise.css`.** Cheapest by a wide margin and
the only option that changes no mechanism. Rejected because it cannot produce
what the page is for: a hero, a five-step timeline, a tabbed screenshot gallery
and a package comparison are components, and expressing them as raw HTML blocks
inside a markdown file produces a document that is harder to read *and* harder
to maintain than either honest form.

**A data-driven static generator — sections as data, rendered to HTML at build
time.** Genuinely attractive: it keeps every property the current mechanism has,
adds full layout control, and would have kept one HTML-producing mechanism
instead of two. Rejected on cost and on fit. It means re-implementing the
component vocabulary the homepage already has as template functions, and giving
up the reveal, theme-swap and screenshot-frame behaviour those components carry
— for a page whose brief was explicitly "like the landing page, or better".

**Vue plus a post-build prerender through headless Chrome.** Both sets of
properties, and the CDP infrastructure exists in `scripts/screenshots/`.
Rejected for now: it puts a Chrome dependency and a fragile step into the deploy
build to buy a property this page does not need. It remains the upgrade path if
that judgement turns out to be wrong.

## Consequences

**Easier.** The page can carry components, per-language screenshots and a form.
Copy lives in a module that a gate can compare across languages. Adding a
section is adding a row to a list.

**Harder.** Two HTML-producing mechanisms now coexist; `routes.js` is what keeps
them from drifting, and it refuses to load if one route is claimed twice. The
title, description and `h1` exist in both the entry's head and the content
module, so an equality gate is required rather than optional. A second language
is now two files instead of one markdown twin.

**Requires care.** Vite's dev server serves the *homepage* at `/enterprise`:
`htmlFallbackMiddleware` only tries `<url>/index.html` when the URL already ends
in a slash, and otherwise tries `<url>.html`, which misses. Without a middleware
the page looks absent in review while the build output is perfect. This is a
lying development server, and the mitigation is a plugin, not a convention.

**Follow-ups this creates**, each its own task: the docroot serves a generated
directory page in place rather than redirecting to its trailing slash (a
canonical that redirects is a canonical a crawler distrusts, and `/privacy`,
`/support` and `/docs/api` have the same wart today); a generated `sitemap.xml`
and a `robots.txt`, neither of which the site has ever had; and `og:image`
becoming a file that is actually in the docroot — the current one answers 200
with the HTML of the homepage, because the catch-all rewrite serves `index.html`
for anything missing, which is why the gate for it must inspect the built
directory rather than an HTTP status.
