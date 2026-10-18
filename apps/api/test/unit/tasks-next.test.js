import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
  budgetProblems,
  criticalAreas,
  criticalHits,
  nextTaskId,
  parseTasks,
  rootBudgetProblems,
  sectionKey,
} from '../../../../scripts/tasks/tasks.mjs';

/// ADR-0042, ADR-0060 — `npm run next` picks the work and `check:docs` polices
/// the backlog through the same reading of TASKS.md. These pin that reading: what
/// a task is, when it is closed or parked, which one is next, which ones touch a
/// critical path, and the exit codes the phase workflow reads (0 ready · 3 only
/// parked · 4 nothing open · 5 over budget).

const NEXT = fileURLToPath(new URL('../../../../scripts/tasks/next.mjs', import.meta.url));

const BACKLOG = `# TASKS

> intro

## Sahibin adımını bekleyen işler

### OPH-100 — Store review ⏸️ SAHİP

- [ ] owner submits the form

## Epic 34 — Widgets

The epic's goal.

### OPH-101 — First widget

- [x] model
- [ ] view

### OPH-102 ★ — Second widget

- [ ] everything, including \`src/routes/sync.js\`

### OPH-103 — Waits on the store ⏸ SAHİP

- [ ] after OPH-100

## Epic E35 — Next epic

### OPH-104 — Later

- [ ] later

## Backlog / parking lot

### A parking sub-heading

- [ ] a stray box that belongs to no task
`;

const SYNC_RULE = `---
paths:
  - "apps/api/src/routes/sync.js"
  - "apps/app/lib/src/sync/**"
---
# Sync
`;

/** A repo root with docs/{TASKS,STATE,LESSONS}.md and one critical-path rule file. */
function tasksFile(text) {
  const root = mkdtempSync(join(tmpdir(), 'tasks-next-'));
  const dir = join(root, 'docs');
  mkdirSync(dir);
  mkdirSync(join(root, '.claude/rules'), { recursive: true });
  writeFileSync(join(root, '.claude/rules/sync.md'), SYNC_RULE);
  writeFileSync(join(dir, 'TASKS.md'), text);
  writeFileSync(join(dir, 'STATE.md'), '# STATE\n');
  writeFileSync(join(dir, 'LESSONS.md'), '# LESSONS\n');
  return { root, dir, path: join(dir, 'TASKS.md') };
}

function next(path, ...args) {
  const r = spawnSync(process.execPath, [NEXT, '--todo', path, ...args], { encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}

describe('parseTasks', () => {
  const { sections, tasks } = parseTasks(BACKLOG);
  const byId = Object.fromEntries(tasks.map((t) => [t.id, t]));

  test('sections: "Epic 34" and "Epic E35" become E34 / E35, others keep their title', () => {
    expect(sections.map((s) => s.key)).toEqual([
      'Sahibin adımını bekleyen işler',
      'E34',
      'E35',
      'Backlog / parking lot',
    ]);
    expect(sectionKey('Epic 7 — x')).toBe('E7');
  });

  test('tasks: the id, the title without the ★ and dash, and the section', () => {
    expect(tasks.map((t) => t.id)).toEqual(['OPH-100', 'OPH-101', 'OPH-102', 'OPH-103', 'OPH-104']);
    expect(byId['OPH-102'].title).toBe('Second widget');
    expect(byId['OPH-101'].section).toBe('E34');
  });

  test('⏸️ parks a task with or without the variation selector', () => {
    expect(byId['OPH-100'].parked).toBe(true);
    expect(byId['OPH-103'].parked).toBe(true);
    expect(byId['OPH-101'].parked).toBe(false);
  });

  test('a box left open keeps a task open; a non-task ### heading ends the block', () => {
    expect(byId['OPH-101'].closed).toBe(false);
    // Without the reset the stray [x] would be OPH-201's, and a gate reading boxes would
    // call an open task closed.
    const [task] = parseTasks('## S\n### OPH-201 — a\n- [ ] a\n### Notes\n- [x] stray\n').tasks;
    expect(task.boxes).toEqual([' ']);
  });

  test('closed: every box [x]/[~], or a box-less ✅ heading', () => {
    const closed = parseTasks(
      '## E\n### OPH-201 — a\n- [x] a\n- [~] b\n### OPH-202 — b ✅\n### OPH-203 — c\n',
    ).tasks;
    expect(closed.map((t) => t.closed)).toEqual([true, true, false]);
  });

  test('ids past 999 still parse (OPH-1000 has no word boundary after three digits)', () => {
    expect(parseTasks('## S\n### OPH-1000 — a\n- [ ] a\n').tasks.map((t) => t.id)).toEqual([
      'OPH-1000',
    ]);
  });

  test('the next task is the first open, unparked one in file order', () => {
    expect(nextTaskId(parseTasks(BACKLOG))).toBe('OPH-101');
    expect(nextTaskId(parseTasks('## S\n### EE-019 — owner ⏸️\n- [ ] x\n'))).toBeNull();
  });
});

describe('next (the CLI)', () => {
  test('prints the next task with its epic intro, exit 0', () => {
    const { path } = tasksFile(BACKLOG);
    const r = next(path);
    expect(r.code).toBe(0);
    expect(r.out).toContain('### OPH-101 — First widget');
    expect(r.out).toContain("The epic's goal.");
    expect(r.out).not.toContain('OPH-102');
  });

  test('--list: every ready task by epic, ⚠ on a critical path, parked ones apart', () => {
    const { path } = tasksFile(BACKLOG);
    const r = next(path, '--list');
    expect(r.code).toBe(0);
    expect(r.out).toMatch(/E34 Epic 34 — Widgets {2}\(2 ready\)/);
    expect(r.out).toMatch(/OPH-102 +⚠ sync +Second widget/);
    expect(r.out).toMatch(/OPH-101 +First widget/);
    expect(r.out).toContain('waiting on the owner (2)');
    const json = JSON.parse(next(path, '--list', '--json').out);
    expect(json.phases.map((p) => [p.id, p.tasks.map((t) => t.id)])).toEqual([
      ['E34', ['OPH-101', 'OPH-102']],
      ['E35', ['OPH-104']],
    ]);
    expect(json.phases[0].intro).toBe("The epic's goal.");
    expect(json.phases[0].tasks[1]).toMatchObject({ critical: ['sync'] });
    expect(json.parked.map((t) => t.id)).toEqual(['OPH-100', 'OPH-103']);
  });

  test('--phase and --only narrow the scope; an unknown phase is an error', () => {
    const { path } = tasksFile(BACKLOG);
    expect(JSON.parse(next(path, '--phase', 'E35', '--json').out).tasks[0].id).toBe('OPH-104');
    expect(
      JSON.parse(next(path, '--list', '--phase', '34', '--json').out).phases.map((p) => p.id),
    ).toEqual(['E34']);
    expect(
      JSON.parse(next(path, '--list', '--only', 'OPH-104,OPH-102', '--json').out).phases.flatMap(
        (p) => p.tasks.map((t) => t.id),
      ),
    ).toEqual(['OPH-102', 'OPH-104']);
    expect(next(path, '--phase', 'E99').code).toBe(1);
  });

  test('only parked tasks left → exit 3 and the list of what they wait on', () => {
    const { path } = tasksFile('## S\n### OPH-201 — owner step ⏸️ SAHİP\n- [ ] x\n');
    const r = next(path);
    expect(r.code).toBe(3);
    expect(r.out).toContain('OPH-201 — owner step');
  });

  test('nothing open → exit 4; --summary reports the counts with the same codes', () => {
    const { path } = tasksFile('# TASKS\n\n## Backlog / parking lot\n\n- an idea\n');
    expect(next(path).code).toBe(4);
    const summary = next(tasksFile(BACKLOG).path, '--summary', '--json');
    expect(summary.code).toBe(0);
    expect(JSON.parse(summary.out)).toMatchObject({
      open: 5,
      actionable: 3,
      parked: ['OPH-100', 'OPH-103'],
    });
  });

  test('--check-budget exits 5 over a budget and names the file', () => {
    const { dir, path } = tasksFile(`${BACKLOG}\n${'x'.repeat(2100)}\n`);
    const r = next(path, '--check-budget');
    expect(r.code).toBe(5);
    expect(r.out).toContain('TASKS.md:');
    expect(budgetProblems(dir)).toEqual([
      {
        file: 'TASKS.md',
        kind: 'line',
        line: BACKLOG.split('\n').length + 1,
        size: 2100,
        limit: 2000,
      },
    ]);
  });

  test('--check-budget also holds the root contract: AGENTS.md lines, rule files', () => {
    const { root, path } = tasksFile(BACKLOG);
    writeFileSync(join(root, 'AGENTS.md'), 'rule\n'.repeat(121));
    writeFileSync(join(root, 'CLAUDE.md'), '@AGENTS.md\n');
    const r = next(path, '--check-budget');
    expect(r.code).toBe(5);
    expect(r.out).toContain('AGENTS.md: 121 lines, budget 120');
    writeFileSync(join(root, 'AGENTS.md'), 'rule\n'.repeat(120));
    expect(next(path, '--check-budget').code).toBe(0);
    writeFileSync(join(root, '.claude/rules/sync.md'), `${SYNC_RULE}${'x\n'.repeat(60)}`);
    expect(rootBudgetProblems(root)).toEqual([
      { file: '.claude/rules/sync.md', kind: 'lines', size: 66, limit: 60 },
    ]);
  });
});

describe('critical paths', () => {
  const { root } = tasksFile(BACKLOG);
  const areas = criticalAreas(root);
  const task = (body) => ({ heading: '### OPH-900 — x', body: [body] });

  test('the globs come from the rule file front matter', () => {
    expect(areas.map((a) => a.area)).toEqual(['sync']);
    expect(criticalHits(task('edit apps/app/lib/src/sync/engine.dart'), areas)).toEqual(['sync']);
    expect(criticalHits(task('edit apps/api/src/routes/tasks.js'), areas)).toEqual([]);
  });

  test('a task may name its area outright', () => {
    expect(criticalHits(task('Kritik yol: sync.'), areas)).toEqual(['sync']);
    expect(criticalHits(task('Critical path.'), areas)).toEqual(['critical']);
  });
});
