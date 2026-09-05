#!/usr/bin/env node
// EE-144 — every page in the docroot is present and a crawler can read it.
//
// This was eight `grep`s inside ci.yml. It moved here for one reason: a gate
// that only runs in CI is a gate you cannot prove, and this repo has already
// paid for that — five red commits in a row, because a suite that could not be
// run locally was marked "NOT RUN" and never looked at. `npm run check:pages`
// runs the same assertions on a built `dist/` in under a second.
//
// It also had to change shape. The bash version matched raw lines, so it only
// ever covered the GENERATED pages: `apps/landing/index.html` writes its
// `<meta name="description">` across three lines and closes its canonical with
// ` />`, and both would have failed a line-oriented grep. That is why the
// homepage — the site's most important page — was outside the gate that checks
// whether pages are indexable. Flattening first means the gate asserts what the
// head SAYS rather than how wide the editor was that last touched it.
//
// The assertions are the SEO facts Lighthouse would check. Nothing in this repo
// runs Lighthouse, and for a static document its SEO category is exactly this
// list: a title, a description, a canonical, a language, a viewport, a heading,
// and no noindex. A page that loses one is still a valid page, which is why
// nothing else would notice.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { SITE_ROUTES, canonicalUrl, distPath } from './routes.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.resolve(here, '../dist');

/** Collapse the document to one line so a tag split across lines still matches. */
const flatten = (html) => html.replace(/\s+/g, ' ');

const problems = [];
const fail = (route, message) => problems.push(`/${route} ${message}`);

if (SITE_ROUTES.length === 0) {
  console.error('::error::the route list is empty — nothing was checked');
  process.exit(1);
}

for (const { route, kind } of SITE_ROUTES) {
  const file = path.join(DIST, distPath(route));
  if (!existsSync(file)) {
    fail(route, `was not built (${kind}); expected dist/${distPath(route)}`);
    continue;
  }

  const flat = flatten(readFileSync(file, 'utf8'));
  const canonical = canonicalUrl(route);

  if (!/<title>\s*[^<\s]/.test(flat)) fail(route, 'has no title');
  if (!/<meta name="description" content="\s*[^"\s]/.test(flat)) {
    fail(route, 'has no meta description');
  }
  // Stops before the closing bracket on purpose: the hand-written entries close
  // with ` />` and the generated ones with `>`.
  if (!flat.includes(`<link rel="canonical" href="${canonical}"`)) {
    fail(route, `has a missing or wrong canonical (expected ${canonical})`);
  }
  if (!/<html lang="[a-z]{2}"/.test(flat)) fail(route, 'declares no language');
  if (!flat.includes('<meta name="viewport"')) fail(route, 'has no viewport');
  if (!/<h1[\s>]/.test(flat)) fail(route, 'has no h1');
  if (flat.includes('noindex')) fail(route, 'is marked noindex');
}

if (problems.length) {
  for (const p of problems) console.error(`::error::${p}`);
  console.error(`\n${problems.length} problem(s) across ${SITE_ROUTES.length} pages.`);
  process.exit(1);
}

console.log(`✓ pages: ${SITE_ROUTES.length} routes built, titled, canonical and indexable`);
