import { STATIC_PAGES } from './static-pages.js';

/**
 * Every page in the docroot, in one list.
 *
 * There are two mechanisms now. `static-pages.js` renders repo markdown into
 * HTML at build time; `VUE_PAGES` are Vite HTML entries with a hand-written
 * head and a Vue body (ADR-0036). Both write `<route>/index.html` into the same
 * `dist/`, and from Apache's point of view — and a crawler's — they are the
 * same kind of thing.
 *
 * That is exactly why this file exists rather than each mechanism guarding its
 * own pages. `static-pages.js` already carries the warning, from the time its
 * gate held a hand-typed copy of four routes: *a gate whose set excludes the
 * new thing is indistinguishable, in the log, from a gate that passed.* A
 * second producer is the event that warning was about. So the build, the dev
 * server, the sitemap and CI all read this list, and a page cannot arrive by a
 * new mechanism and be invisible to the checks.
 */

/**
 * Pages that are their own Vite HTML entry.
 *
 * `entry` is relative to `apps/landing/` because Vite mirrors that path into
 * `dist/` verbatim (it emits `path.relative(root, id)`), which is what makes a
 * route a real directory in the docroot. An entry outside this directory would
 * be written outside `outDir`.
 */
export const VUE_PAGES = Object.freeze([
  { route: '', entry: 'index.html', lang: 'en' },
  { route: 'tr', entry: 'tr/index.html', lang: 'tr' },
  { route: 'enterprise', entry: 'enterprise/index.html', lang: 'en' },
  { route: 'enterprise/tr', entry: 'enterprise/tr/index.html', lang: 'tr' },
]);

/** Every indexable HTML page in the docroot, however it was produced. */
export const SITE_ROUTES = Object.freeze([
  ...VUE_PAGES.map(({ route, lang }) => ({ route, lang, kind: 'vue' })),
  ...STATIC_PAGES.map(({ route, lang }) => ({ route, lang, kind: 'markdown' })),
]);

/**
 * Two producers claiming one `dist/` path is a real possibility while a page is
 * being moved from one mechanism to the other, and Rollup reports it as a
 * fileName conflict raised from inside a plugin — true, and unreadable. Say it
 * here instead, at import time, with the route in the message.
 */
const seen = new Set();
for (const { route } of SITE_ROUTES) {
  if (seen.has(route)) {
    throw new Error(
      `routes.js: /${route} is produced twice — a Vite entry and the markdown ` +
        `generator are both writing dist/${route}/index.html`,
    );
  }
  seen.add(route);
}

/**
 * The Vite entry a request URL should be served by, or null.
 *
 * Exported rather than closed over inside `vite.config.js` so it can be
 * asserted without starting a server — the mistake this whole function exists
 * to correct is one nobody notices by looking.
 *
 * Handles `/enterprise`, `/enterprise/`, and either with a query string. The
 * homepage is excluded because Vite already serves `<root>/index.html` for `/`.
 */
export function entryForUrl(url) {
  const [pathname] = (url ?? '/').split('?');
  const clean = pathname.replace(/\/+$/, '');
  const page = VUE_PAGES.find((p) => p.route !== '' && clean === `/${p.route}`);
  return page ? page.entry : null;
}

/** Where a route's built page lands, relative to `dist/`. */
export function distPath(route) {
  return route === '' ? 'index.html' : `${route}/index.html`;
}

/** The canonical URL a route must declare. */
export function canonicalUrl(route) {
  return `https://alliswell.space/${route}`;
}
