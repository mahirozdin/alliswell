#!/usr/bin/env node
// `npm run next` — print the next task (or a batch of them) from docs/TASKS.md.
//
// Why a script: the selection rule lives here instead of in a conversation, where
// it would be lost at the next context compaction, and an agent reads the slice it
// needs instead of the whole backlog. The rule itself is in ./tasks.mjs, shared
// with `check:docs` so the two can never disagree about what is next.
//
//   npm run next                      the next task, its epic's intro and its block
//   npm run next -- --batch 4         up to 4 ready tasks from the same epic (one loop turn)
//   npm run next -- --summary         open/ready/parked per epic + a loop iteration limit
//   npm run next -- --check-budget    the working docs' byte budgets (check:docs runs the same)
//   --json · --phase E34[,E35] · --only OPH-351,OPH-352 · --cross-phase · --todo <path>
//
// Exit codes (a loop's stop condition reads these, not prose):
//   0 a task is ready · 3 only parked tasks remain (waiting on the owner)
//   4 nothing is open · 5 a budget is exceeded (--check-budget) · 1 error
import { existsSync, readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { budgetProblems, parseTasks } from './tasks.mjs';

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
      batch: { type: 'string', default: '1' },
      summary: { type: 'boolean', default: false },
      'check-budget': { type: 'boolean', default: false },
      json: { type: 'boolean', default: false },
      phase: { type: 'string' },
      only: { type: 'string' },
      'cross-phase': { type: 'boolean', default: false },
    },
  }));
} catch (error) {
  fail(`next: ${error.message}`);
}

const todo = resolve(args.todo);
if (!existsSync(todo))
  fail(`next: ${args.todo} not found (run from the repo root, or pass --todo)`);
const shown = relative(process.cwd(), todo) || todo;

if (args['check-budget']) {
  const problems = budgetProblems(dirname(todo));
  if (args.json) {
    console.log(JSON.stringify({ problems }));
  } else if (problems.length === 0) {
    console.log(`✓ working docs within budget (${relative(process.cwd(), dirname(todo)) || '.'})`);
  } else {
    console.log('✗ working docs over budget — every session and loop turn pays for these bytes:');
    for (const p of problems) {
      if (p.kind === 'missing') console.log(`  ${p.file}: missing`);
      else if (p.kind === 'size') console.log(`  ${p.file}: ${p.size} bytes, budget ${p.limit}`);
      else console.log(`  ${p.file}:${p.line}: ${p.size}-byte line, budget ${p.limit}`);
    }
  }
  process.exit(problems.length ? 5 : 0);
}

const batchSize = Number.parseInt(args.batch, 10);
if (!Number.isInteger(batchSize) || batchSize < 1) fail('next: --batch takes a positive integer');

const { sections, tasks } = parseTasks(readFileSync(todo, 'utf8'));
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
  const size = batchSize > 1 ? batchSize : 4;
  // One turn per batch, plus two for a red batch gate and a red CI to fix.
  const suggested = ready.length ? Math.max(3, Math.ceil(ready.length / size) + 2) : 0;
  if (args.json) {
    console.log(
      JSON.stringify({
        phases: rows,
        open: open.length,
        actionable: ready.length,
        parked: parked.map((t) => t.id),
        suggested_max_iterations: suggested,
        batch_size: size,
      }),
    );
  } else {
    console.log(
      `${shown}: ${open.length} open · ${ready.length} ready · ${parked.length} parked (waiting on the owner)`,
    );
    for (const r of rows) {
      // An epic shows its key (the --phase argument); any other section just its title.
      const label = /^E\d+$/.test(r.phase) ? `${r.phase} ${r.title}` : r.title;
      console.log(
        `  ${label.slice(0, 64).padEnd(64)} open ${String(r.open).padStart(3)}` +
          `  ready ${String(r.ready).padStart(3)}  ⏸ ${String(r.parked).padStart(3)}`,
      );
    }
    if (suggested) {
      console.log(`Loop: batch ${size} → --max-iterations ${suggested}`);
    }
  }
  process.exit(code);
}

if (code === 4) {
  console.log(args.json ? JSON.stringify({ status: 'done' }) : `✓ nothing open in ${shown}.`);
  process.exit(4);
}

if (code === 3) {
  if (args.json) {
    console.log(JSON.stringify({ status: 'parked_only', parked: parked.map((t) => t.id) }));
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
const batch = [first];
for (const t of ready.slice(1)) {
  if (batch.length >= batchSize) break;
  if (t.section !== first.section && !args['cross-phase'] && !only) break;
  batch.push(t);
}
const section = sections.find((s) => s.key === first.section);
const trimmed = (lines, limit) => {
  // Collapse blank runs, cap the length, drop the trailing blank.
  const squeezed = lines.filter((l, i) => l.trim() || (i > 0 && lines[i - 1].trim()));
  const kept = squeezed.slice(0, limit);
  while (kept.length && !kept[kept.length - 1].trim()) kept.pop();
  if (squeezed.length > limit) kept.push(`… (+${squeezed.length - limit} lines in ${shown})`);
  return kept;
};

if (args.json) {
  console.log(
    JSON.stringify({
      status: 'ready',
      phase: section ? { id: section.key, title: section.title } : null,
      tasks: batch.map((t) => ({
        id: t.id,
        title: t.title,
        line: t.line,
        text: [t.heading, ...t.body].join('\n').trim(),
      })),
      open: open.length,
      ready: ready.length,
    }),
  );
  process.exit(0);
}

console.log(
  `${batch.length > 1 ? `NEXT BATCH (${batch.length})` : 'NEXT TASK'} — ${section ? section.title : '(no section)'}`,
);
const intro = section ? trimmed(section.intro, INTRO_LINES) : [];
if (intro.some((l) => l.trim())) {
  console.log('');
  for (const l of intro) console.log(`  ${l}`);
}
for (const t of batch) {
  console.log(`\n${t.heading}   (${shown}:${t.line})`);
  for (const l of trimmed(t.body, BODY_LINES)) console.log(l);
}
console.log(
  `\n${open.length} open · ${ready.length} ready · ${parked.length} parked. ` +
    'Close each task with its narrow check (npm run verify:task), the batch with npm run verify:batch.',
);
process.exit(0);
