import { SITE_ROUTES, canonicalUrl } from './routes.js';

/**
 * `sitemap.xml`, generated from the one route list (EE-154).
 *
 * The site has never had one. Writing it by hand would be a second copy of
 * `SITE_ROUTES` in a file nothing checks — the exact sin `static-pages.js`
 * names in its own header, and the reason `routes.js` exists at all. So it is
 * emitted at build time from the same list the build, the dev server and the
 * gates read, and a page added to that list is in the sitemap the same day.
 *
 * ── WHAT IS DELIBERATELY NOT IN IT ────────────────────────────────────────
 *
 * No `lastmod`. The honest value is the date the page's SOURCE last changed,
 * and this plugin does not know that — it would have to be the build date,
 * which makes every page look freshly written on every deploy. A crawler that
 * learns your lastmod is noise stops reading it, so an absent one is worth more
 * than a wrong one.
 *
 * No `priority` or `changefreq` either. Google has said for years that it
 * ignores both.
 *
 * ── THE ALTERNATES ARE THE POINT ──────────────────────────────────────────
 *
 * A paired page carries `xhtml:link` alternates naming every language INCLUDING
 * itself, which is what tells a crawler that `/enterprise` and `/enterprise/tr`
 * are one page in two languages rather than two pages competing for the same
 * queries. It is the same claim the `<head>` makes; a sitemap that disagreed
 * with the head would be worse than one that said nothing.
 */

/** `/x/tr` ↔ `/x` — the pairing the site actually uses. */
function twinOf(route) {
  return route.endsWith('/tr') ? route.slice(0, -3) : `${route}/tr`;
}

function alternatesFor(route, known) {
  const twin = twinOf(route);
  if (!known.has(twin)) return [];
  const [en, tr] = route.endsWith('/tr') ? [twin, route] : [route, twin];
  return [
    { hreflang: 'en', href: canonicalUrl(en) },
    { hreflang: 'tr', href: canonicalUrl(tr) },
    { hreflang: 'x-default', href: canonicalUrl(en) },
  ];
}

export function renderSitemap() {
  const known = new Set(SITE_ROUTES.map((r) => r.route));
  const urls = SITE_ROUTES.map(({ route }) => {
    const links = alternatesFor(route, known)
      .map((a) => `    <xhtml:link rel="alternate" hreflang="${a.hreflang}" href="${a.href}"/>`)
      .join('\n');
    return `  <url>\n    <loc>${canonicalUrl(route)}</loc>${links ? `\n${links}` : ''}\n  </url>`;
  });

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls.join('\n')}
</urlset>
`;
}

/** Vite plugin: emits the sitemap, and serves it from the dev server. */
export function sitemapPlugin() {
  return {
    name: 'alliswell-sitemap',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if ((req.url ?? '').split('?')[0] !== '/sitemap.xml') return next();
        res.setHeader('Content-Type', 'application/xml; charset=utf-8');
        res.end(renderSitemap());
      });
    },
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'sitemap.xml', source: renderSitemap() });
    },
  };
}
