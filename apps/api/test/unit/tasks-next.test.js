import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
  budgetProblems,
  nextTaskId,
  parseTasks,
  sectionKey,
} from '../../../../scripts/tasks/tasks.mjs';

/// ADR-0042 — `npm run next` picks the work and `check:docs` polices the
/// backlog through the same reading of TASKS.md. These pin that reading: what
/// a task is, when it is closed or parked, which one is next, and the exit
/// codes a loop's stop condition is built on (0 ready · 3 only parked · 4
/// nothing open · 5 over budget).

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

- [ ] everything

### OPH-103 — Waits on the store ⏸ SAHİP

- [ ] after OPH-100

## Epic E35 — Next epic

### OPH-104 — Later

- [ ] later

## Backlog / parking lot

### A parking sub-heading

- [ ] a stray box that belongs to no task
`;

function tasksFile(text) {
  const dir = mkdtempSync(join(tmpdir(), 'tasks-next-'));
  writeFileSync(join(dir, 'TASKS.md'), text);
  writeFileSync(join(dir, 'STATE.md'), '# STATE\n');
  writeFileSync(join(dir, 'LESSONS.md'), '# LESSONS\n');
  return { dir, path: join(dir, 'TASKS.md') };
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

  test('--batch stays inside the epic and skips parked tasks', () => {
    const { path } = tasksFile(BACKLOG);
    const r = next(path, '--batch', '5', '--json');
    expect(r.code).toBe(0);
    expect(JSON.parse(r.out).tasks.map((t) => t.id)).toEqual(['OPH-101', 'OPH-102']);
  });

  test('--phase and --only narrow the scope; an unknown phase is an error', () => {
    const { path } = tasksFile(BACKLOG);
    expect(JSON.parse(next(path, '--phase', 'E35', '--json').out).tasks[0].id).toBe('OPH-104');
    expect(
      JSON.parse(next(path, '--only', 'OPH-104,OPH-102', '--batch', '4', '--json').out).tasks.map(
        (t) => t.id,
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
    const summary = next(tasksFile(BACKLOG).path, '--summary', '--batch', '2', '--json');
    expect(summary.code).toBe(0);
    expect(JSON.parse(summary.out)).toMatchObject({
      open: 5,
      actionable: 3,
      parked: ['OPH-100', 'OPH-103'],
      suggested_max_iterations: 4,
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
});
