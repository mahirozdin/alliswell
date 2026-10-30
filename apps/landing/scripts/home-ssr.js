import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { SSR_PAGES } from './routes.js';

/**
 * The homepage is rendered to HTML on the server and hydrated in the browser
 * (ADR-0061). Before that it shipped an empty `#app` and a paragraph saying
 * the page needed JavaScript, which is all a crawler, a link preview or a
 * reader with scripting off ever saw.
 *
 * Two producers write the same document: `prerender.mjs` after `vite build`,
 * and the dev middleware below on every request. Both go through `inject()`,
 * so a page that renders in dev renders the same way in the build.
 */

export const OUTLET = '<!--ssr-outlet-->';
export const HEAD = '<!--ssr-head-->';

/**
 * Put the rendered app and head into an HTML shell.
 *
 * Each marker must appear exactly once. A missing marker would ship the empty
 * shell again with every check green; a doubled one would render the page
 * twice. Both are errors, raised here with the reason in the message.
 */
export function inject(html, { app, head }) {
  for (const marker of [OUTLET, HEAD]) {
    const count = html.split(marker).length - 1;
    if (count !== 1) {
      throw new Error(`home-ssr: expected ${marker} exactly once in the HTML shell, found ${count}`);
    }
  }
  // A replacer function, not a string: `$&` and `$'` in rendered text (a
  // shell command, a price) would otherwise be read as replacement patterns.
  return html.replace(HEAD, () => head).replace(OUTLET, () => app);
}

/** The SSR page a dev request asks for, or null. */
function pageFor(url) {
  const [pathname] = (url ?? '/').split('?');
  const clean = pathname.replace(/\/index\.html$/, '').replace(/\/+$/, '');
  return SSR_PAGES.find((p) => clean === (p.route === '' ? '' : `/${p.route}`)) ?? null;
}

/**
 * Dev server: answer `/` and `/tr` with the rendered page.
 *
 * Registered after `mpaRoutesPlugin`, which has already rewritten `/tr` to
 * `/tr/index.html`. The braces in `configureServer` are load-bearing for the
 * same reason they are in vite.config.js: a returned function would run after
 * Vite's own HTML middleware, which serves the empty shell first.
 */
export function homeSsrPlugin() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  return {
    name: 'alliswell-home-ssr',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const page = pageFor(req.url);
        if (!page || req.method !== 'GET') {
          next();
          return;
        }
        try {
          const shell = readFileSync(path.join(root, page.entry), 'utf8');
          const html = await server.transformIndexHtml(req.originalUrl ?? req.url, shell);
          const { render } = await server.ssrLoadModule('/src/home/entry-server.js');
          const out = inject(html, await render(page.lang));
          res.statusCode = 200;
          res.setHeader('Content-Type', 'text/html; charset=utf-8');
          res.end(out);
        } catch (error) {
          server.ssrFixStacktrace(error);
          next(error);
        }
      });
    },
  };
}
