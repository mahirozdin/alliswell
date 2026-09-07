import { copyFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

import { entryForUrl, VUE_PAGES } from './scripts/routes.js';
import { sitemapPlugin } from './scripts/sitemap.js';
import { staticPagesPlugin } from './scripts/static-pages.js';

/**
 * Serves a Vite HTML entry at the URL its directory will have in production.
 *
 * Vite's dev server does NOT do this. `htmlFallbackMiddleware` tries
 * `<url>/index.html` only when the URL already ends in a slash, and otherwise
 * tries `<url>.html` — so `/enterprise` misses both, falls through to the SPA
 * fallback and renders the HOMEPAGE. Silently. The page looks absent in review
 * while the build output is perfect, or worse looks fine at `/enterprise/` and
 * broken at the URL everybody actually types.
 *
 * This is a lying development server, so the mitigation is a plugin rather than
 * a convention. `configureServer` bodies register before every Vite internal,
 * so a rewritten `req.url` is picked up by htmlFallback downstream;
 * `configurePreviewServer` does the same for `vite preview`.
 */
function mpaRoutesPlugin() {
  const rewrite = (req) => {
    const url = req.url ?? '/';
    const entry = entryForUrl(url);
    if (!entry) return;
    const query = url.includes('?') ? url.slice(url.indexOf('?')) : '';
    req.url = `/${entry}${query}`;
  };
  // The braces are load-bearing. `configureServer` treats a RETURNED function
  // as a post-hook to run after Vite's own middleware, and
  // `server.middlewares.use()` returns connect's app — which Vite then called
  // with no arguments, crashing the dev server before it could listen with
  // "Cannot read properties of undefined (reading 'url')". An arrow with an
  // expression body returns that value; this one returns nothing.
  const use = (server) => {
    server.middlewares.use((req, _res, next) => {
      rewrite(req);
      next();
    });
  };
  return { name: 'alliswell-mpa-routes', configureServer: use, configurePreviewServer: use };
}

/**
 * Vite's `public/` copy step SKIPS dotfiles, so `.htaccess` — the one file that
 * makes `/` and `/app` coexist in a single docroot — silently never reaches
 * `dist/`. The deploy then ships a docroot with no rewrite rules and every deep
 * link 404s. Copy them explicitly once the bundle is written.
 */
function copyDotfilesFromPublic() {
  return {
    name: 'alliswell-copy-public-dotfiles',
    apply: 'build',
    closeBundle() {
      const from = path.resolve(fileURLToPath(new URL('./public', import.meta.url)));
      const to = path.resolve(fileURLToPath(new URL('./dist', import.meta.url)));
      if (!existsSync(from)) return;
      for (const name of readdirSync(from)) {
        if (!name.startsWith('.')) continue;
        copyFileSync(path.join(from, name), path.join(to, name));
        this.info?.(`copied ${name} → dist/`);
      }
    },
  };
}

/**
 * The landing site is served from the ROOT of alliswell.space; the Flutter web
 * app lives under `/app` (built separately with `--base-href /app/`). Keeping
 * the two as different bases is what lets one Apache docroot host both without
 * either one's router swallowing the other's URLs.
 */
export default defineConfig({
  base: '/',
  // MPA, not SPA. Without this a mistyped URL in `vite dev` or `vite preview`
  // silently renders the homepage instead of 404ing, which is how a broken
  // route survives review. Production's catch-all is the DEPLOYMENT's decision
  // (a deep link into /app must reach the app), not the dev server's.
  appType: 'mpa',
  plugins: [
    vue(),
    mpaRoutesPlugin(),
    staticPagesPlugin(),
    sitemapPlugin(),
    copyDotfilesFromPublic(),
  ],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    // Screenshots are the payload here — inlining them as data URIs would
    // bloat the entry chunk and delay first paint.
    assetsInlineLimit: 2048,
    rollupOptions: {
      // Derived from VUE_PAGES so a page added to that list becomes an entry
      // without a second edit here. Named keys rather than an array so the
      // entry chunks are `assets/enterprise-HASH.js` and not three files all
      // called `index-HASH.js`.
      //
      // NOTE: specifying `input` at all means Vite stops adding `<root>/
      // index.html` implicitly — the homepage has to be in the list, and it is.
      input: Object.fromEntries(
        VUE_PAGES.map((p) => [
          p.route === '' ? 'index' : p.route.replace(/\//g, '-'),
          fileURLToPath(new URL(`./${p.entry}`, import.meta.url)),
        ]),
      ),
      output: {
        manualChunks: undefined,
      },
    },
  },
  server: {
    port: 5173,
    strictPort: false,
  },
});
