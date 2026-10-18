// The one reading of a TASKS.md, shared by every tool that needs it.
//
// `npm run next` picks work from the backlog and `check:docs` polices it. Parsed
// twice, the two could disagree about which task is open — and a loop would pick
// work the gate calls finished, or skip work the gate says is next. So both call
// this module. An extension checked out beside the core may call it too (it may
// know the core; nothing here knows it).
//
// The format, as docs/TASKS.md states it for people:
//   ## Epic 34 — Title        a section; "Epic 34" and "Epic E21" become the keys E34 / E21
//   ### OPH-351 — Title       a task (a ★ may sit before the dash); its block runs to the
//                             next ## or ### heading
//   - [ ] / - [x] / - [~]     its boxes — all [x]/[~], or a box-less ✅ heading, is closed
//   ⏸️ in the heading         parked: it waits on the owner (an account, a console, a store
//                             review), so it is never picked; STATE must name it
//
// The next task is the first open, unparked task in file order — epics are ordered and
// a task's order inside its epic is its dependency order. That is the rule the
// extension's docs gate already enforced for its pointer; there is deliberately no
// second, finer dependency syntax that one of the two readers would not know.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const SECTION = /^## (.+?)\s*$/;
// Three digits or more: `\d{3}\b` alone would not see OPH-1000 at all (no word boundary
// after its third digit), and the task would vanish from both `next` and the gate.
const TASK = /^### ([A-Z]{2,5}-\d{3,})\b(.*)$/;
const BOX = /^\s*- \[([ xX~])\]/;
// ⏸️ is U+23F8 plus a variation selector; match the base code point so both spellings count.
const PARKED = '⏸';

/** "Epic 34 — …" → "E34", "Epic E21 — …" → "E21", anything else → its text before the dash. */
export function sectionKey(title) {
  const epic = /^Epic\s+E?(\d+)\b/i.exec(title);
  if (epic) return `E${Number(epic[1])}`;
  return title.split(/\s+[—–]\s+/)[0].trim();
}

/**
 * @param {string} text  contents of a TASKS.md
 * @returns {{ sections: Array<{key: string, title: string, line: number, intro: string[]}>,
 *             tasks: Array<{id: string, title: string, heading: string, line: number,
 *                           section: string|null, boxes: string[], body: string[],
 *                           parked: boolean, closed: boolean, ready: boolean}> }}
 */
export function parseTasks(text) {
  const sections = [];
  const tasks = [];
  let section = null;
  let task = null;
  text.split('\n').forEach((line, i) => {
    const s = SECTION.exec(line);
    if (s) {
      section = { key: sectionKey(s[1]), title: s[1], line: i + 1, intro: [] };
      sections.push(section);
      task = null;
      return;
    }
    if (/^# /.test(line)) {
      section = null;
      task = null;
      return;
    }
    const t = TASK.exec(line);
    if (t) {
      task = {
        id: t[1],
        title: t[2].replace(/^\s*★?\s*[—–-]\s*/, '').trim(),
        heading: line,
        line: i + 1,
        section: section ? section.key : null,
        boxes: [],
        body: [],
        parked: line.includes(PARKED),
      };
      tasks.push(task);
      return;
    }
    // A ### heading that is not a task (the parking lot's sub-headings) ends the block.
    if (/^### /.test(line)) {
      task = null;
      return;
    }
    if (task) {
      task.body.push(line);
      const box = BOX.exec(line);
      if (box) task.boxes.push(box[1].toLowerCase());
    } else if (section) {
      section.intro.push(line);
    }
  });
  for (const t of tasks) {
    t.closed = t.boxes.length > 0 ? !t.boxes.includes(' ') : t.heading.includes('✅');
    t.ready = !t.closed && !t.parked;
  }
  return { sections, tasks };
}

/** The id `next` would print, or null when nothing is ready. */
export function nextTaskId(parsed) {
  const first = parsed.tasks.find((t) => t.ready);
  return first ? first.id : null;
}

// ── Budgets ─────────────────────────────────────────────────────────────────
//
// STATE.md and TASKS.md are read at the start of every session and every loop
// turn; by 2026-09-26 they had grown to 484 KB and 932 KB (and the extension's to
// 787 KB and 1.07 MB), almost all of it history nobody needed but everybody paid
// for. LESSONS.md is searched by area rather than read whole, so it gets room, but
// not unlimited room. A single line has a ceiling too: the table cell that grows by
// one sentence a session is how a 22 KB "current status" line happened elsewhere.
export const WORKING_DOC_BUDGETS = {
  'STATE.md': { bytes: 16_000, lineBytes: 2_000 },
  'TASKS.md': { bytes: 150_000, lineBytes: 2_000 },
  'LESSONS.md': { bytes: 48_000 },
};

/**
 * @param {string} docsDir  the directory holding STATE.md, TASKS.md and LESSONS.md
 * @returns {Array<{file: string, kind: 'missing'|'size'|'line', size?: number,
 *                  limit: number, line?: number}>}
 */
export function budgetProblems(docsDir) {
  const problems = [];
  for (const [file, budget] of Object.entries(WORKING_DOC_BUDGETS)) {
    const path = join(docsDir, file);
    if (!existsSync(path)) {
      problems.push({ file, kind: 'missing', limit: budget.bytes });
      continue;
    }
    const text = readFileSync(path, 'utf8');
    const size = Buffer.byteLength(text);
    if (size > budget.bytes) problems.push({ file, kind: 'size', size, limit: budget.bytes });
    if (!budget.lineBytes) continue;
    text.split('\n').forEach((line, i) => {
      const bytes = Buffer.byteLength(line);
      if (bytes > budget.lineBytes) {
        problems.push({ file, kind: 'line', line: i + 1, size: bytes, limit: budget.lineBytes });
      }
    });
  }
  return problems;
}

// ── The root contract ───────────────────────────────────────────────────────
//
// AGENTS.md — and CLAUDE.md, which imports it — is loaded into every session, every
// workflow agent and every context after a compaction; an import does not make it
// cheaper. By 2026-10-18 it had grown to 236 lines and 16 KB, most of it detail that
// one task in ten needed. Codex truncates its AGENTS.md chain at 32 KiB without a
// word, so past a point the rules at the bottom are simply not there. The detail now
// lives in docs/development/ and in path-scoped rules (.claude/rules/, loaded when a
// matching file is touched); these numbers keep it there (ADR-0060).
export const ROOT_DOC_BUDGETS = {
  'AGENTS.md': { lines: 120, bytes: 10_240 },
  'CLAUDE.md': { lines: 20, bytes: 2_048 },
};
export const RULES_DIR = '.claude/rules';
export const RULE_MAX_LINES = 60;
export const ROOT_CHAIN_BYTES = 24 * 1024;

const lineCount = (text) => text.split('\n').length - (text.endsWith('\n') ? 1 : 0);

/**
 * @param {string} root  the repository root
 * @returns {Array<{file: string, kind: 'lines'|'size'|'chain', size: number, limit: number}>}
 */
export function rootBudgetProblems(root) {
  const problems = [];
  const chain = new Set();
  for (const [file, budget] of Object.entries(ROOT_DOC_BUDGETS)) {
    const path = join(root, file);
    if (!existsSync(path)) continue;
    const text = readFileSync(path, 'utf8');
    const lines = lineCount(text);
    const bytes = Buffer.byteLength(text);
    if (lines > budget.lines)
      problems.push({ file, kind: 'lines', size: lines, limit: budget.lines });
    if (bytes > budget.bytes)
      problems.push({ file, kind: 'size', size: bytes, limit: budget.bytes });
    chain.add(file);
    for (const m of text.matchAll(/^@(\S+)/gm)) chain.add(m[1]);
  }
  const chainBytes = [...chain]
    .filter((f) => existsSync(join(root, f)))
    .reduce((sum, f) => sum + Buffer.byteLength(readFileSync(join(root, f))), 0);
  if (chainBytes > ROOT_CHAIN_BYTES) {
    problems.push({
      file: [...chain].join(' + '),
      kind: 'chain',
      size: chainBytes,
      limit: ROOT_CHAIN_BYTES,
    });
  }
  for (const rule of ruleFiles(root)) {
    const lines = lineCount(readFileSync(join(root, rule), 'utf8'));
    if (lines > RULE_MAX_LINES) {
      problems.push({ file: rule, kind: 'lines', size: lines, limit: RULE_MAX_LINES });
    }
  }
  return problems;
}

function ruleFiles(root) {
  const dir = join(root, RULES_DIR);
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith('.md'))
    .sort()
    .map((f) => `${RULES_DIR}/${f}`);
}

// ── Critical paths ──────────────────────────────────────────────────────────
//
// A critical path is an area where a mistake is expensive or irreversible (AGENTS.md
// "Critical paths"). Each has a rule file whose `paths:` front matter is the one list
// of its globs — Claude loads the file when a matching path is touched, and `next`
// reads the same globs to mark a task ⚠ when its text names such a path, so the phase
// workflow can give that task the area's extra gate. A task may also say so outright
// ("Kritik yol: sync." / "Critical path: sync.").

/** "apps/api/migrations/**" → a RegExp over repo-relative paths. */
function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      re += '.*';
      i += 1;
      if (glob[i + 1] === '/') i += 1;
    } else if (c === '*') re += '[^/]*';
    else if (c === '{') {
      const end = glob.indexOf('}', i);
      const options = glob.slice(i + 1, end).split(',');
      re += `(?:${options.map((o) => o.replace(/[.+^$()|[\]\\]/g, '\\$&')).join('|')})`;
      i = end;
    } else re += c.replace(/[.+?^$()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

/**
 * @param {string} root  the repository root
 * @returns {Array<{area: string, file: string, globs: RegExp[]}>}
 */
export function criticalAreas(root) {
  return ruleFiles(root).map((file) => {
    const text = readFileSync(join(root, file), 'utf8');
    const front = /^---\n([\s\S]*?)\n---/.exec(text);
    const globs = front
      ? [...front[1].matchAll(/^\s*-\s*["']?([^"'\n]+?)["']?\s*$/gm)].map((m) => globToRegExp(m[1]))
      : [];
    return { area: file.replace(/^.*\/|\.md$/g, ''), file, globs };
  });
}

/** The critical areas a task touches: named outright, or through a path in its text. */
export function criticalHits(task, areas) {
  const text = [task.heading, ...task.body].join('\n');
  const hits = new Set();
  for (const m of text.matchAll(/(?:kritik yol|critical path)\s*[:—–-]?\s*([a-z][\w-]*)?/gi)) {
    const area = m[1] && areas.find((a) => a.area === m[1].toLowerCase());
    hits.add(area ? area.area : 'critical');
  }
  // Task text often names a path from inside its app ("src/routes/sync.js").
  const paths = (text.match(/[\w.-]+(?:\/[\w.*-]+)+/g) ?? []).flatMap((p) => {
    const bare = p.replace(/^\.\//, '');
    return [bare, `apps/api/${bare}`, `apps/app/${bare}`];
  });
  for (const area of areas) {
    if (paths.some((p) => area.globs.some((g) => g.test(p)))) hits.add(area.area);
  }
  return [...hits];
}
