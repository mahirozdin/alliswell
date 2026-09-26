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
//
// Since 2026-09-26 it also keeps the working docs small and STATE's pointer
// honest — see `workingDocProblems()` below.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';
import { budgetProblems, nextTaskId, parseTasks } from '../tasks/tasks.mjs';

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
  // The landing page's JSON-LD. Hand-written in `index.html`, one layer below
  // the banner above — and the guard that was extended to catch the banner
  // walked straight past it, because it scans `content.js` and not the HTML
  // shell. It shipped 1.6.0 into the v1.7.0 deploy (OPH-274). This is the
  // version claim SEARCH ENGINES read, so it is the one that outlives a
  // reader noticing.
  /"softwareVersion":\s*"(\d+\.\d+\.\d+)"/g,
];

/** Every .html/.js under a directory, skipping build output and vendor trees. */
function walkLanding(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'dist' || entry.name === 'shots') {
      continue;
    }
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walkLanding(full, out);
    else if (/\.(html|js)$/.test(entry.name)) out.push(full);
  }
  return out;
}

function claimFiles() {
  // EE-144 — this used to name three paths by hand: README, content.js and
  // index.html. OPH-274 happened because a live claim sat one file away from a
  // list exactly like it, and the enterprise work adds two more HTML shells and
  // two content modules that would each have been outside the gate on the day
  // they were written. Walking the tree brings them in on that day instead of
  // on the day somebody notices the version on a page is a release behind.
  const out = [join(ROOT, 'README.md'), ...walkLanding(join(ROOT, 'apps/landing'))];
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
  // The string the app SHOWS in Settings > About. `release.yml` has gated on
  // this since it sat at 0.1.0 for three releases — but only at TAG time, which
  // means the first anyone learned of a drift was a failed release. Round 19
  // hit exactly that. Checking it here moves the discovery to `npm run
  // check:docs`, where every other version claim is already caught.
  const shownFile = join(ROOT, 'apps/app/lib/src/core/app_version.dart');
  const shown = /^const kAppVersion = '(\d+\.\d+\.\d+)'/m.exec(read(shownFile));
  if (!shown) problems.push('apps/app/lib/src/core/app_version.dart: no parsable `kAppVersion`');
  else if (shown[1] !== VERSION) {
    problems.push(
      `apps/app/lib/src/core/app_version.dart: kAppVersion ${shown[1]} != root ${VERSION}`,
    );
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

// ── The working docs stay small ───────────────────────────────────────────────
//
// STATE.md and TASKS.md are read at the start of every agent session. By
// 2026-09-26 they had grown to 484 KB and 932 KB: every finished task kept its
// whole narrative, and every Snapshot cell carried an "Önceki metin:" chain of
// all its earlier values. Little of it was wrong and almost none of it was
// needed, but all of it was paid for on every session. The cleanup cut them to
// the pointer, the owner's decisions and the open work; durable lessons moved
// to LESSONS.md, which is searched by area rather than read whole.
//
// A byte budget alone would let the files fill up again and fail on some random
// later day, so the habits that grew them fail on the day they come back:
//   1. A closed task is deleted, not ticked — git history and CHANGELOG are its
//      record. A task whose boxes are all `[x]`/`[~]` (or a box-less heading
//      with ✅) may not stay in TASKS.md.
//   2. A Snapshot cell is overwritten, never chained: "Önceki metin" fails.
//   3. STATE.md, TASKS.md and LESSONS.md have byte budgets, and STATE/TASKS a
//      per-line one (scripts/tasks/tasks.mjs holds the numbers).
//
// And since `npm run next` picks the work, two copies of "what is next" exist —
// STATE's pointer cell and the backlog itself — so the pointer must agree:
//   4. "➡️ Next task" names the task `next` would print, or declares
//      **BACKLOG BOŞ** when none is ready. A half-finished session close
//      (task deleted, arrow not moved) fails here instead of misleading the
//      next session.
//   5. Every ⏸️ task is named somewhere in STATE: a task parked on the owner that
//      the owner's list does not mention waits forever.
// TASKS.md is read through the same module as `next`, so the gate and the
// picker cannot disagree about which task is open.
const DRAINED = '**BACKLOG BOŞ**';

function workingDocProblems() {
  const problems = [];
  for (const p of budgetProblems(join(ROOT, 'docs'))) {
    const file = `docs/${p.file}`;
    if (p.kind === 'missing') problems.push(`${file}: missing`);
    else if (p.kind === 'size') {
      problems.push(`${file}: ${p.size} bytes, budget ${p.limit} — condense it; it is not a log`);
    } else {
      problems.push(
        `${file}:${p.line}: a ${p.size}-byte line, budget ${p.limit} — a cell that grows every ` +
          'session; overwrite it',
      );
    }
  }
  if (!existsSync(join(ROOT, 'docs/STATE.md')) || !existsSync(join(ROOT, 'docs/TASKS.md'))) {
    return problems;
  }

  const state = read(join(ROOT, 'docs/STATE.md'));
  state.split('\n').forEach((line, i) => {
    if (line.includes('Önceki metin')) {
      problems.push(
        `docs/STATE.md:${i + 1}: an "Önceki metin" chain — overwrite the cell; git keeps the old value`,
      );
    }
  });

  const parsed = parseTasks(read(join(ROOT, 'docs/TASKS.md')));
  for (const task of parsed.tasks) {
    if (task.closed) {
      problems.push(
        `docs/TASKS.md: ${task.id} is closed but still listed — delete its block ` +
          '(a lasting lesson goes to LESSONS.md, an owner decision to STATE.md)',
      );
    }
  }

  const next = nextTaskId(parsed);
  const pointer = /Next task\*\*\s*\|\s*\*\*([A-Z]{2,5}-\d{3,})/.exec(state);
  const drained = /Next task\*\*\s*\|\s*\*\*BACKLOG BOŞ\*\*/.test(state);
  if (!pointer && !drained) {
    problems.push(
      `docs/STATE.md: no "➡️ **Next task** | **OPH-NNN" cell — write the id \`npm run next\` ` +
        `prints, or ${DRAINED} when nothing is ready`,
    );
  } else if (next && drained) {
    problems.push(`docs/STATE.md says ${DRAINED} but ${next} is ready — point the cell at it`);
  } else if (!next && pointer) {
    problems.push(
      `docs/STATE.md points at ${pointer[1]} but no task is ready — write ${DRAINED} ` +
        '(and why in "Current phase")',
    );
  } else if (next && pointer && pointer[1] !== next) {
    problems.push(`docs/STATE.md points at ${pointer[1]}, but the next task is ${next}`);
  }

  for (const task of parsed.tasks.filter((t) => t.parked && !t.closed)) {
    if (!state.includes(task.id)) {
      problems.push(
        `docs/STATE.md: ${task.id} is parked (⏸️) but STATE never names it — list the owner's ` +
          'step under "Kullanıcıdan bekleyen"',
      );
    }
  }
  return problems;
}

const problems = [...manifestProblems(), ...docProblems()];
const working = workingDocProblems();

if (problems.length > 0) {
  console.error(`✗ docs: ${problems.length} stale version claim(s) — repo is ${VERSION}\n`);
  for (const p of problems) console.error(`  ${p}`);
  console.error(
    '\nUpdate the claim, or mark a deliberately historical line with `docs-check-ignore`.',
  );
}
if (working.length > 0) {
  console.error(`✗ docs: ${working.length} working-doc problem(s)\n`);
  for (const p of working) console.error(`  ${p}`);
}
if (problems.length > 0 || working.length > 0) process.exit(1);

console.log(
  `✓ docs: version claims agree with package.json (${VERSION}); ` +
    'STATE/TASKS/LESSONS within their rules, STATE points where `npm run next` does',
);
