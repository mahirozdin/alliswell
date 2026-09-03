#!/usr/bin/env node
// OPH-293 — fail CI on a bare `FloatingActionButton.extended`.
//
// The app theme sets `shape: CircleBorder()` for every FAB flavour, and this
// Flutter's `FloatingActionButtonThemeData` has no separate slot for the
// extended one. A circle on a ~145x48 button paints a 48px disc centred
// horizontally, so the icon at x≈16-40 lands outside it and vanishes — the
// label straddles the edge and survives. It reads as a missing glyph, which
// is exactly how it was reported and exactly the wrong place to look.
//
// The fix is one property, `shape: StadiumBorder()`, and every call site had
// to remember it. Of the three that existed, two did not — including the one
// on the API keys screen that a user hit. `AwExtendedFab` remembers once;
// this guard is what makes "once" true, in the spirit of check:no-ts and
// check:i18n. A rule nobody can verify mechanically WILL be broken again.
//
// Escape hatch for a genuine exception: `// fab-ignore` on the line.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const LIB = resolve(here, '../../apps/app/lib');
const CWD = process.cwd();

// The widget that owns the shape is allowed to name the thing it wraps.
const ALLOWED_FILE = join(LIB, 'src/widgets/fabs.dart');

const PATTERN = /FloatingActionButton\.extended/;

function dartFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...dartFiles(full));
    else if (entry.endsWith('.dart')) out.push(full);
  }
  return out;
}

const violations = [];
for (const file of dartFiles(LIB)) {
  if (file === ALLOWED_FILE) continue;
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (line.includes('fab-ignore')) return;
    if (PATTERN.test(line)) {
      violations.push({ file: relative(CWD, file), line: i + 1, text: line.trim() });
    }
  });
}

if (violations.length > 0) {
  console.error('Bare FloatingActionButton.extended found. Use AwExtendedFab');
  console.error('(lib/src/widgets/fabs.dart) — the theme\'s CircleBorder clips');
  console.error('an extended FAB and eats its icon.\n');
  for (const v of violations) console.error(`  ${v.file}:${v.line}  ${v.text}`);
  console.error(`\n${violations.length} violation(s).`);
  process.exit(1);
}

console.log('check:fab — no bare extended FABs.');
