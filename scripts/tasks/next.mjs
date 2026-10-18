#!/usr/bin/env node
// `npm run next` — print the next task, or every task an agent can do, from docs/TASKS.md.
//
// Why a script: the selection rule lives here instead of in a conversation, where
// it would be lost at the next context compaction, and an agent reads the slice it
// needs instead of the whole backlog. The rule itself is in ./tasks.mjs, shared
// with `check:docs` so the two can never disagree about what is next.
//
//   npm run next                      the next task, its epic's intro and its block
//   npm run next -- --list            every ready task, by epic, ⚠ on critical paths (/isler)
//   npm run next -- --list --phase E35 --json
//                                     an epic's ready tasks with their full text (/faz)
//   npm run next -- --summary         open/ready/parked per epic
//   npm run next -- --check-budget    the working docs' and the root contract's budgets
//   --json · --phase E34[,E35] · --only OPH-351,OPH-352 · --todo <path> · --root <dir>
//
// A "phase" in the phase workflow (docs/development/workflow.md) is an epic: `E35`.
//
// Exit codes (scripts read these, not prose):
//   0 a task is ready · 3 only parked tasks remain (waiting on the owner)
//   4 nothing is open · 5 a budget is exceeded (--check-budget) · 1 error
import { existsSync, readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import {
  budgetProblems,
  criticalAreas,
  criticalHits,
  parseTasks,
  rootBudgetProblems,
} from './tasks.mjs';

const BODY_LINES = 60;
const INTRO_LINES = 20;

function fail(message) {
  console.error(message);
  process.exit(1);
}

let args;
try {
  ({ values: args } = parseArgs({
    options: {
      todo: { type: 'string', default: 'docs/TASKS.md' },
      root: { type: 'string' },
      list: { type: 'boolean', default: false },
      summary: { type: 'boolean', default: false },
      'check-budget': { type: 'boolean', default: false },
      json: { type: 'boolean', default: false },
      phase: { type: 'string' },
      only: { type: 'string' },
    },
  }));
} catch (error) {
  fail(`next: ${error.message}`);
}

const todo = resolve(args.todo);
if (!existsSync(todo))
  fail(`next: ${args.todo} not found (run from the repo root, or pass --todo)`);
const shown = relative(process.cwd(), todo) || todo;
// TASKS.md lives in docs/; the root contract one level up.
const root = resolve(args.root ?? resolve(dirname(todo), '..'));

if (args['check-budget']) {
  const working = budgetProblems(dirname(todo));
  const rooted = rootBudgetProblems(root);
  if (args.json) {
    console.log(JSON.stringify({ problems: [...working, ...rooted] }));
  } else if (working.length + rooted.length === 0) {
    console.log('✓ working docs and the root contract within budget');
  } else {
    console.log('✗ over budget — every session and every agent pays for these bytes:');
    for (const p of working) {
      if (p.kind === 'missing') console.log(`  ${p.file}: missing`);
      else if (p.kind === 'size') console.log(`  ${p.file}: ${p.size} bytes, budget ${p.limit}`);
      else console.log(`  ${p.file}:${p.line}: ${p.size}-byte line, budget ${p.limit}`);
    }
    for (const p of rooted) {
      const unit = p.kind === 'lines' ? 'lines' : 'bytes';
      console.log(
        `  ${p.file}: ${p.size} ${unit}, budget ${p.limit}${p.kind === 'chain' ? ' (import chain)' : ''}`,
      );
    }
  }
  process.exit(working.length + rooted.length ? 5 : 0);
}

const { sections, tasks } = parseTasks(readFileSync(todo, 'utf8'));
const areas = criticalAreas(root);
const list = (value) =>
  value
    ? value
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean)
    : null;
const phases = list(args.phase)?.map((p) => (/^\d+$/.test(p) ? `E${p}` : p.toUpperCase()));
const only = list(args.only)?.map((id) => id.toUpperCase());
if (phases) {
  const known = new Set(sections.map((s) => s.key.toUpperCase()));
  const missing = phases.filter((p) => !known.has(p));
  if (missing.length) {
    fail(`next: no section ${missing.join(', ')} in ${shown} (have: ${[...known].join(', ')})`);
  }
}
const inScope = (t) =>
  (!phases || phases.includes(String(t.section).toUpperCase())) && (!only || only.includes(t.id));

const scoped = tasks.filter(inScope);
const open = scoped.filter((t) => !t.closed);
const ready = open.filter((t) => t.ready);
const parked = open.filter((t) => t.parked);
const code = ready.length ? 0 : open.length ? 3 : 4;
// An epic shows its key (the --phase argument); any other section just its title.
const label = (s) => (/^E\d+$/.test(s.key) ? `${s.key} ${s.title}` : s.title);

if (args.summary) {
  const rows = sections
    .map((s) => {
      const own = scoped.filter((t) => t.section === s.key);
      return {
        phase: s.key,
        title: s.title,
        open: own.filter((t) => !t.closed).length,
        ready: own.filter((t) => t.ready).length,
        parked: own.filter((t) => !t.closed && t.parked).length,
      };
    })
    .filter((r) => r.open > 0);
  if (args.json) {
    console.log(
      JSON.stringify({
        phases: rows,
        open: open.length,
        actionable: ready.length,
        parked: parked.map((t) => t.id),
      }),
    );
  } else {
    console.log(
      `${shown}: ${open.length} open · ${ready.length} ready · ${parked.length} parked (waiting on the owner)`,
    );
    for (const r of rows) {
      console.log(
        `  ${label({ key: r.phase, title: r.title }).slice(0, 64).padEnd(64)} open ${String(r.open).padStart(3)}` +
          `  ready ${String(r.ready).padStart(3)}  ⏸ ${String(r.parked).padStart(3)}`,
      );
    }
  }
  process.exit(code);
}

const trimmed = (lines, limit) => {
  // Collapse blank runs, cap the length, drop the trailing blank.
  const squeezed = lines.filter((l, i) => l.trim() || (i > 0 && lines[i - 1].trim()));
  const kept = squeezed.slice(0, limit);
  while (kept.length && !kept[kept.length - 1].trim()) kept.pop();
  if (squeezed.length > limit) kept.push(`… (+${squeezed.length - limit} lines in ${shown})`);
  return kept;
};
const asJson = (t) => ({
  id: t.id,
  title: t.title,
  line: t.line,
  critical: criticalHits(t, areas),
  text: [t.heading, ...t.body].join('\n').trim(),
});

if (args.list) {
  const groups = sections
    .map((s) => ({
      section: s,
      tasks: ready.filter((t) => t.section === s.key),
    }))
    .filter((g) => g.tasks.length > 0);
  if (args.json) {
    console.log(
      JSON.stringify({
        status: code === 0 ? 'ready' : code === 3 ? 'parked_only' : 'done',
        phases: groups.map((g) => ({
          id: g.section.key,
          title: g.section.title,
          intro: trimmed(g.section.intro, INTRO_LINES).join('\n').trim(),
          tasks: g.tasks.map(asJson),
        })),
        parked: parked.map((t) => ({ id: t.id, title: t.title })),
        open: open.length,
        ready: ready.length,
      }),
    );
    process.exit(code);
  }
  if (groups.length === 0) console.log(`No task an agent can do in ${shown}.`);
  for (const g of groups) {
    console.log(`\n${label(g.section)}  (${g.tasks.length} ready)`);
    for (const t of g.tasks) {
      const hits = criticalHits(t, areas);
      const mark = hits.length ? `⚠ ${hits.join(',')}` : '';
      console.log(`  ${t.id.padEnd(9)} ${mark.padEnd(16)} ${t.title.slice(0, 90)}`);
    }
  }
  if (parked.length) {
    console.log(`\n⏸ waiting on the owner (${parked.length}) — not for an agent:`);
    for (const t of parked) console.log(`  ${t.id.padEnd(9)} ${t.title.slice(0, 90)}`);
  }
  console.log(`\n${open.length} open · ${ready.length} ready · ${parked.length} parked.`);
  process.exit(code);
}

if (code === 4) {
  console.log(args.json ? JSON.stringify({ status: 'done' }) : `✓ nothing open in ${shown}.`);
  process.exit(4);
}

if (code === 3) {
  if (args.json) {
    console.log(
      JSON.stringify({
        status: 'parked_only',
        parked: parked.map((t) => t.id),
      }),
    );
  } else {
    console.log(`⏸ no task an agent can do — ${parked.length} parked, waiting on the owner:`);
    for (const t of parked) console.log(`  ${t.id} — ${t.title.slice(0, 90)}`);
    console.log(
      'The owner steps are listed in STATE.md; when one is done, drop the ⏸️ from its task.',
    );
  }
  process.exit(3);
}

const first = ready[0];
const section = sections.find((s) => s.key === first.section);

if (args.json) {
  console.log(
    JSON.stringify({
      status: 'ready',
      phase: section ? { id: section.key, title: section.title } : null,
      tasks: [asJson(first)],
      open: open.length,
      ready: ready.length,
    }),
  );
  process.exit(0);
}

console.log(`NEXT TASK — ${section ? section.title : '(no section)'}`);
const intro = section ? trimmed(section.intro, INTRO_LINES) : [];
if (intro.some((l) => l.trim())) {
  console.log('');
  for (const l of intro) console.log(`  ${l}`);
}
const hits = criticalHits(first, areas);
console.log(`\n${first.heading}   (${shown}:${first.line})`);
if (hits.length) console.log(`⚠ critical path: ${hits.join(', ')} — read .claude/rules/<area>.md`);
for (const l of trimmed(first.body, BODY_LINES)) console.log(l);
console.log(
  `\n${open.length} open · ${ready.length} ready · ${parked.length} parked. ` +
    'Close the task with its narrow check (npm run verify:task); a phase ends with npm run verify:batch + verify:smoke.',
);
process.exit(0);
