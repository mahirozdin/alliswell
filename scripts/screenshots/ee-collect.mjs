#!/usr/bin/env node
// Publishes the enterprise goldens into `screenshots/ee/` (EE-147).
//
// The goldens land in `apps/app/test/goldens/` as `ee-<screen>-<theme>-<lang>`
// and the site wants `screenshots/ee/<screen>-<theme>-<lang>`. That is a rename
// of the `ee-` prefix and nothing else — docs/SCREENSHOTS.md §4b used to ask
// for it by hand, four screens at a time.
//
// WHY THIS IS A SCRIPT AND NOT A `cp`. Its real job is the refusal. A capture
// that was never produced is invisible until the landing build references it,
// and even then CI is the first thing to say so — this says so locally, by
// name, before a reference exists. The list below is therefore the set of
// pictures the page is ALLOWED to use: adding a section to the page means
// adding a name here and producing it, in that order.
//
// Run after a two-locale golden pass:
//
//   cd apps/app
//   flutter test --update-goldens --dart-define=screenshots=true \
//       --dart-define=shotLocale=en test/features/ee/
//   …and again with shotLocale=tr
//   cd ../.. && npm run shots:ee
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../..');
const GOLDENS = path.join(repoRoot, 'apps/app/test/goldens');
const OUT = path.join(repoRoot, 'screenshots/ee');

const THEMES = ['light', 'dark'];
const LOCALES = ['en', 'tr'];

/**
 * Every screen the enterprise page may show, and the claim it stands next to.
 *
 * The reason column is not decoration: a screenshot with no claim beside it is
 * a screenshot that will still be on the page when the claim is gone. When a
 * section is cut, its row is cut with it.
 *
 * A third element `'external'` means the capture is NOT a Flutter golden and is
 * written straight into `screenshots/ee/` by something else — today that is the
 * overlay's `npm run shots:portal` (the request portal's own server-side HTML,
 * EE-149) and `npm run shots:store -- --only ee-hero` (the composite, EE-150). Those are VERIFIED here rather than copied: this
 * script stays the single list of what the page may use, and a portal capture
 * nobody produced is refused by the same message as a missing golden.
 */
const PUBLISHED = [
  ['hero', 'the queue and the promise, in one frame', 'external'],
  ['units-admin', 'the organisation, as its shape'],
  ['units-manager', 'the same team one rung down: what is missing rather than greyed'],
  ['team-roles', 'permissions as a grant matrix, not a handful of fixed roles'],
  ['ticket-queue', 'the queue a unit works from, with the promise on every row'],
  ['ticket-detail', 'one request opened: the internal note, told three ways at once'],
  ['ticket-history', 'and who changed it — including when the answer is not a person'],
  ['services-admin', 'the catalogue: what a company can be asked for'],
  ['service-routing', 'and who answers it — service to unit, refused when nobody does'],
  ['sla-policies', 'targets per priority: first response and resolution'],
  ['sla-calendars', 'a business calendar, so a night shift is one row and not two'],
  ['sla-dashboard', 'what was promised against what happened'],
  ['sla-monitors', 'a watched URL opens one incident, not one a minute'],
  ['portal-links', 'each public form with its expiry, its cap and its revoke switch'],
  ['portal-form', 'and what the stranger sees: no account, no JavaScript', 'external'],
  ['portal-follow', 'then a link that follows it, in five buckets and not seven', 'external'],
  ['team-identity', 'accounts from the directory you already run — LDAP, SAML, OIDC'],
  ['meeting-named', 'a recording that becomes a decision that becomes work'],
];

/**
 * `oxipng` when it is here, nothing when it is not — the defensive shape
 * `sync-screenshots.mjs` uses for `sips`. These files are committed, so the
 * saving is permanent; but a contributor without the tool must still be able
 * to run this.
 */
function optimiser() {
  try {
    execFileSync('oxipng', ['--version'], { stdio: 'ignore' });
    return (file) => execFileSync('oxipng', ['-o', '4', '--strip', 'all', '-q', file]);
  } catch {
    return null;
  }
}

function main() {
  if (!existsSync(GOLDENS)) {
    console.error(
      `✗ ${path.relative(repoRoot, GOLDENS)} does not exist — run the golden ` +
        'pass first (docs/SCREENSHOTS.md §4b).',
    );
    process.exit(1);
  }
  mkdirSync(OUT, { recursive: true });

  const wanted = [];
  for (const [screen, , source] of PUBLISHED) {
    const external = source === 'external';
    for (const theme of THEMES) {
      for (const lang of LOCALES) {
        const to = path.join(OUT, `${screen}-${theme}-${lang}.png`);
        wanted.push({
          external,
          // An external capture is already where it belongs; there is nothing
          // to copy, only something to insist on.
          from: external ? to : path.join(GOLDENS, `ee-${screen}-${theme}-${lang}.png`),
          to,
        });
      }
    }
  }

  const missing = wanted.filter((w) => !existsSync(w.from));
  if (missing.length) {
    const golden = missing.filter((m) => !m.external);
    const external = missing.filter((m) => m.external);
    console.error(`✗ ${missing.length} capture(s) were never produced:\n`);
    for (const m of missing) console.error(`    ${path.basename(m.from)}`);
    if (golden.length) {
      console.error(
        '\nBoth locales have to run. A golden filename carries its language ' +
          '(EE-145), so a single-locale pass produces exactly half of these.',
      );
    }
    if (external.length) {
      const portal = external.some((m) => path.basename(m.from).startsWith('portal-'));
      const hero = external.some((m) => path.basename(m.from).startsWith('hero-'));
      if (portal) {
        console.error(
          '\nThe portal pages are rendered by the overlay, not by a widget test: ' +
            '`cd ee && npm run shots:portal`.',
        );
      }
      if (hero) {
        console.error(
          '\nThe hero is composed from two captures that must exist first: ' +
            '`npm run shots:store -- --only ee-hero`.',
        );
      }
    }
    process.exit(1);
  }

  const optimise = optimiser();
  let bytes = 0;
  for (const w of wanted) {
    if (!w.external) copyFileSync(w.from, w.to);
    if (optimise) optimise(w.to);
    bytes += statSync(w.to).size;
  }

  console.log(
    `✓ ee screenshots: ${wanted.length} files ` +
      `(${PUBLISHED.length} screens × ${THEMES.length} themes × ${LOCALES.length} languages), ` +
      `${(bytes / 1024 / 1024).toFixed(1)} MB` +
      (optimise ? ', oxipng applied' : ' — install oxipng to shrink them'),
  );

  // Anything in the directory that is not on the list is a picture nothing
  // publishes. Say so rather than deleting it: a stale capture is a decision
  // somebody has to make, not a file a script should quietly remove.
  const expected = new Set(wanted.map((w) => path.basename(w.to)));
  const strays = readdirSync(OUT).filter((f) => f.endsWith('.png') && !expected.has(f));
  if (strays.length) {
    console.log(
      `\n· ${strays.length} file(s) here are on no list — publish them by ` +
        'adding their screen to PUBLISHED, or delete them:',
    );
    for (const f of strays) console.log(`    ${f}`);
  }
}

main();
