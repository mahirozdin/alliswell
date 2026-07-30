#!/usr/bin/env node
/**
 * Copies the repo's screenshots into the landing site's `public/` tree.
 *
 * They live at the repo root (`screenshots/`) because the README and the store
 * listings use the same files; duplicating them into the site's source tree
 * would mean two copies that drift. `public/shots` is gitignored and rebuilt
 * from the canonical set on every dev start and every build.
 */
import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../../..');
const from = path.join(repoRoot, 'screenshots');
const to = path.join(here, '..', 'public', 'shots');

if (!existsSync(from)) {
  console.warn(
    `! no screenshots at ${path.relative(repoRoot, from)} — the site will build with empty frames.\n` +
      '  Produce them with: node scripts/screenshots/web.mjs (see docs/SCREENSHOTS.md)',
  );
  await mkdir(to, { recursive: true });
  process.exit(0);
}

await rm(to, { recursive: true, force: true });
await mkdir(to, { recursive: true });
await cp(from, to, { recursive: true });

/**
 * The canonical captures are 2× retina PNGs (a desktop shot is 2880×1800,
 * ~900 kB). That is right for the README and required for the stores, and
 * ruinous for a page that shows fourteen of them — 19 MB of screenshots.
 *
 * So the site's copies are capped at 1600 px on the long edge AND re-encoded as
 * JPEG, which takes the same page to well under 2 MB. Screenshots are flat UI,
 * not gradients-heavy photography, so quality 82 is visually lossless at the
 * sizes these are displayed.
 *
 * Uses macOS `sips`, which is where the captures are produced anyway (the iOS
 * simulator lives there). Anywhere else the PNGs are copied untouched and the
 * page is heavier but correct — a build must never fail over image weight.
 * `imageExt` in the site's markup follows whichever ran.
 */
const MAX_EDGE = 1600;
const JPEG_QUALITY = 82;

function hasSips() {
  const probe = spawnSync('sips', ['--help'], { stdio: 'ignore' });
  return !probe.error;
}

async function* pngsUnder(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* pngsUnder(full);
    else if (entry.name.endsWith('.png')) yield full;
  }
}

const groups = await readdir(to, { withFileTypes: true });
const counts = [];
for (const g of groups) {
  if (!g.isDirectory()) continue;
  counts.push(`${g.name}: ${(await readdir(path.join(to, g.name))).length}`);
}

let converted = 0;
if (hasSips()) {
  for await (const file of pngsUnder(to)) {
    const jpg = file.replace(/\.png$/, '.jpg');
    const out = spawnSync(
      'sips',
      ['-Z', String(MAX_EDGE), '-s', 'format', 'jpeg', '-s', 'formatOptions', String(JPEG_QUALITY), file, '--out', jpg],
      { stdio: 'ignore' },
    );
    if (!out.error && existsSync(jpg)) {
      await rm(file, { force: true });
      converted += 1;
    }
  }
}

// The markup asks for `.jpg`; without a converter the PNGs stay, so leave a
// copy under the expected name rather than shipping a page of broken images.
if (!converted) {
  for await (const file of pngsUnder(to)) {
    await cp(file, file.replace(/\.png$/, '.jpg'));
  }
}

console.log(
  `✓ screenshots synced → public/shots (${counts.join(', ')})` +
    (converted
      ? ` · ${converted} re-encoded ≤${MAX_EDGE}px JPEG q${JPEG_QUALITY}`
      : ' · full-size PNGs aliased as .jpg (no `sips` here)'),
);
