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
 * ── EE-150: THIS USED TO BE `sips` OR NOTHING, AND THE DEPLOY IS LINUX ────
 *
 * The fallback said the page would be "heavier but correct", and that was a
 * defensible trade when eight images were referenced. But `.github/workflows/
 * deploy.yml` runs on `ubuntu-latest`, where there is no `sips` — so the
 * fallback is not a fallback, it is the PRODUCTION path, and alliswell.space
 * has been serving full-size PNG bytes under `.jpg` names since the day it
 * shipped. The enterprise page carries about thirty references, which turns a
 * defensible trade into several megabytes per page load on a sales page.
 *
 * So the encoder is a CHAIN, not one platform's tool: `sips` (macOS, where the
 * captures are produced), then ImageMagick's `magick` or `convert`, which
 * GitHub's ubuntu images carry. The last-resort alias stays, because a build
 * must still never fail over image weight — but the landing CI job now fails
 * when a served JPEG is over 400 kB, so the silent path cannot ship twice.
 */
const MAX_EDGE = 1600;
const JPEG_QUALITY = 82;

/**
 * The first encoder on this machine, or null.
 *
 * Each entry returns the argv that turns `input` into `output` at
 * `MAX_EDGE`/`JPEG_QUALITY`. ImageMagick's `>` suffix means "only shrink",
 * which is what `sips -Z` does.
 */
const ENCODERS = [
  {
    bin: 'sips',
    probe: ['--help'],
    argv: (i, o) => [
      '-Z', String(MAX_EDGE),
      '-s', 'format', 'jpeg',
      '-s', 'formatOptions', String(JPEG_QUALITY),
      i, '--out', o,
    ],
  },
  {
    bin: 'magick',
    probe: ['-version'],
    argv: (i, o) => [i, '-resize', `${MAX_EDGE}x${MAX_EDGE}>`, '-quality', String(JPEG_QUALITY), o],
  },
  {
    bin: 'convert',
    probe: ['-version'],
    argv: (i, o) => [i, '-resize', `${MAX_EDGE}x${MAX_EDGE}>`, '-quality', String(JPEG_QUALITY), o],
  },
];

/**
 * A probe must check the EXIT STATUS, not just whether the process spawned.
 *
 * `spawnSync().error` is set only when the binary cannot be executed at all.
 * A binary that exists and exits non-zero — a shim, a broken install, a
 * `sips` on a machine where it refuses — comes back with `error: undefined`
 * and `status: 127`, so an `!error` probe ACCEPTS it, the chain stops at a
 * tool that cannot encode, and the fallback then reports that no encoder was
 * found at all. Measured with a stub on PATH while ImageMagick was installed:
 * the run aliased every PNG and printed "no sips, magick or convert here",
 * which was false in both halves.
 */
function usable(e) {
  const probe = spawnSync(e.bin, e.probe, { stdio: 'ignore' });
  return !probe.error && probe.status === 0;
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

// Try each encoder in turn and stop at the first that actually converts
// something. A tool that passes its own `--version` and then fails on every
// file is a tool that has not been ruled out by the probe alone.
let converted = 0;
let encoder = null;
for (const candidate of ENCODERS) {
  if (!usable(candidate)) continue;
  for await (const file of pngsUnder(to)) {
    const jpg = file.replace(/\.png$/, '.jpg');
    const out = spawnSync(candidate.bin, candidate.argv(file, jpg), { stdio: 'ignore' });
    if (!out.error && out.status === 0 && existsSync(jpg)) {
      await rm(file, { force: true });
      converted += 1;
    }
  }
  if (converted > 0) {
    encoder = candidate;
    break;
  }
}

// The markup asks for `.jpg`; with no encoder at all the PNGs stay, so leave a
// copy under the expected name rather than shipping a page of broken images.
// This is now the LAST resort rather than the second one, and the landing CI
// job fails on the weight it produces.
if (!converted) {
  for await (const file of pngsUnder(to)) {
    await cp(file, file.replace(/\.png$/, '.jpg'));
  }
}

console.log(
  `✓ screenshots synced → public/shots (${counts.join(', ')})` +
    (converted
      ? ` · ${converted} re-encoded ≤${MAX_EDGE}px JPEG q${JPEG_QUALITY} (${encoder?.bin})`
      : ' · ⚠ full-size PNGs aliased as .jpg — no sips, magick or convert here'),
);
