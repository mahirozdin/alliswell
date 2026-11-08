import { render as renderEnterprise } from './enterprise/entry-server.js';
import { render as renderHome } from './home/entry-server.js';

/**
 * The one server entry (ADR-0061; the enterprise pages since OPH-413).
 *
 * `vite build --ssr src/entry-server.js` builds this, scripts/prerender.mjs
 * and the dev middleware in scripts/home-ssr.js call it with a route's `page`
 * and `lang` from scripts/routes.js. Each render returns the app markup, the
 * extra head tags, the hero title and the section headings the prerender
 * asserts are on the page.
 */
const PAGES = { home: renderHome, enterprise: renderEnterprise };

export async function render(page, lang) {
  const fn = PAGES[page];
  if (!fn) throw new Error(`entry-server: no page called "${page}"`);
  return fn(lang);
}
