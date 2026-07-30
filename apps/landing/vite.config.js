import { copyFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

import { legalPagesPlugin } from './scripts/legal-pages.js';

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
  plugins: [vue(), legalPagesPlugin(), copyDotfilesFromPublic()],
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
