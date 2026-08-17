#!/usr/bin/env node
// Epic 24 follow-up — fail CI when the docs assert a version the repo has left
// behind. This mirrors `check:no-ts` and `check:i18n`.
//
// Why a guard rather than another careful edit: the marketing docs carry live
// facts, and live facts rot. The "measured contradictions" table in TASKS was
// fixed once and had drifted again within days — `docs/COMPARISON.md` still
// said "We are at 1.4.0" at 1.6.0, and README's exact test counts went stale
// twice in two commits, both times because of work in this very repo. A number
// nobody can verify mechanically WILL be wrong; the honest options are to gate
// it or to stop asserting it.
//
// So: versions are gated here (one source of truth, exact match), and the test
// counts were changed to a form that does not rot ("1,200+") instead of being
// policed by a gate that would need a full suite run to have an opinion.
//
// Escape hatch for a deliberately historical statement — e.g. "researched
// against v1.4.0", which is provenance and not a claim about today: put
// `docs-check-ignore` on the line.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '../..');
const CWD = process.cwd();

const rel = (p) => relative(CWD, p);
const read = (p) => readFileSync(p, 'utf8');

/** The one source of truth. Everything else is compared against it. */
const VERSION = JSON.parse(read(join(ROOT, 'package.json'))).version;

// Append-only logs and backlogs are history by definition: every past entry
// names the version it shipped in, and rewriting them would be a lie.
const SKIP_FILES = new Set(['CHANGELOG.md', 'STATE.md', 'TASKS.md', 'ROADMAP.md']);

/**
 * Statements that assert what the version IS right now. Each pattern must
 * capture the version in group 1. Deliberately narrow: a broad "any X.Y.Z"
 * sweep would flag competitor versions, dependency pins and changelog prose,
 * and a guard that cries wolf gets ignored, which is worse than no guard.
 */
const CLAIMS = [
  /\bWe are at\s+v?(\d+\.\d+\.\d+)/g,
  /\bProject status\s*[—-]\s*`v(\d+\.\d+\.\d+)`/g,
  /\bcurrently (?:at|on)\s+v?(\d+\.\d+\.\d+)/g,
  /\bThe current (?:release|version) is\s+v?(\d+\.\d+\.\d+)/g,
  // The landing page's own banner. Not markdown, and the most VISIBLE version
  // claim we ship — it sat at 1.4.0 through two releases, in the hero, while
  // the first draft of this guard was busy reading only `docs/*.md`.
  /^export const VERSION = '(\d+\.\d+\.\d+)'/gm,
];

function claimFiles() {
  const out = [join(ROOT, 'README.md'), join(ROOT, 'apps/landing/src/content.js')];
  const docs = join(ROOT, 'docs');
  for (const entry of readdirSync(docs)) {
    if (entry.endsWith('.md') && !SKIP_FILES.has(entry)) out.push(join(docs, entry));
  }
  return out;
}

/** Every workspace manifest and pubspec must agree with the root version. */
function manifestProblems() {
  const problems = [];
  // Read the list from `workspaces` rather than naming packages here: hardcoding
  // two of them is how `@alliswell/landing` sat at 1.4.0 through two releases.
  const root = JSON.parse(read(join(ROOT, 'package.json')));
  for (const workspace of root.workspaces ?? []) {
    const manifest = join(ROOT, workspace, 'package.json');
    const { version } = JSON.parse(read(manifest));
    if (version !== VERSION) {
      problems.push(`${workspace}/package.json: version ${version} != root ${VERSION}`);
    }
  }
  // pubspec carries a build number too: `1.6.0+26`.
  const pubspec = read(join(ROOT, 'apps/app/pubspec.yaml'));
  const found = /^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$/m.exec(pubspec);
  if (!found) problems.push('apps/app/pubspec.yaml: no parsable `version:` line');
  else if (found[1] !== VERSION) {
    problems.push(`apps/app/pubspec.yaml: version ${found[1]} != root ${VERSION}`);
  }
  return problems;
}

function docProblems() {
  const problems = [];
  for (const file of claimFiles()) {
    const lines = read(file).split('\n');
    lines.forEach((line, i) => {
      if (line.includes('docs-check-ignore')) return;
      for (const pattern of CLAIMS) {
        pattern.lastIndex = 0;
        let match;
        while ((match = pattern.exec(line)) !== null) {
          if (match[1] !== VERSION) {
            problems.push(`${rel(file)}:${i + 1}: claims ${match[1]}, repo is ${VERSION}\n    ${line.trim()}`);
          }
        }
      }
    });
  }
  return problems;
}

const problems = [...manifestProblems(), ...docProblems()];

if (problems.length > 0) {
  console.error(`✗ docs: ${problems.length} stale version claim(s) — repo is ${VERSION}\n`);
  for (const p of problems) console.error(`  ${p}`);
  console.error(
    '\nUpdate the claim, or mark a deliberately historical line with `docs-check-ignore`.',
  );
  process.exit(1);
}

console.log(`✓ docs: version claims agree with package.json (${VERSION})`);
