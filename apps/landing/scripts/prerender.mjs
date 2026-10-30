#!/usr/bin/env node
/**
 * Write the server-rendered homepage into `dist/` (ADR-0061).
 *
 * Runs after `vite build` (the client bundle, which wrote the HTML shells with
 * their hashed assets) and `vite build --ssr` (the render function). For each
 * SSR page it renders the app, puts it into the built shell and writes it
 * back, then deletes the SSR bundle so nothing server-side reaches the docroot.
 *
 * deploy.yml runs `landing:build` and none of the CI checks, so the assertions
 * that matter for a crawler live here, inside the build: one <h1>, the hero's
 * own words, and no marker left behind.
 */
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { HEAD, OUTLET, inject } from './home-ssr.js';
import { SSR_PAGES, distPath } from './routes.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ssrDir = path.join(root, 'node_modules/.cache/landing-ssr');
const { render } = await import(pathToFileURL(path.join(ssrDir, 'entry-server.js')).href);

const problems = [];
for (const page of SSR_PAGES) {
  const file = path.join(root, 'dist', distPath(page.route));
  const rendered = await render(page.lang);
  const html = inject(readFileSync(file, 'utf8'), rendered);
  const h1s = html.match(/<h1[\s>]/g)?.length ?? 0;
  if (h1s !== 1) problems.push(`/${page.route}: ${h1s} <h1> elements, expected exactly one`);
  if (html.includes(OUTLET) || html.includes(HEAD)) problems.push(`/${page.route}: an SSR marker survived`);
  if (!html.includes(rendered.title)) problems.push(`/${page.route}: the hero title is not in the HTML`);
  writeFileSync(file, html);
  console.log(`prerendered /${page.route} (${Math.round(html.length / 1024)} kB)`);
}
rmSync(ssrDir, { recursive: true, force: true });
if (problems.length) {
  console.error(problems.map((p) => `prerender: ${p}`).join('\n'));
  process.exit(1);
}
