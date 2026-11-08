#!/usr/bin/env node
// OPH-399 (ADR-0063 #5) — a ratchet on hand-made type and spacing in the app.
//
// DESIGN §3.3 says "use textTheme roles; never ad-hoc fontSize" and §3.2 says
// "no off-grid values". Neither rule had a gate, and the research count found
// 19 raw `fontSize:`, ~50 raw `TextStyle(` and ~50 off-grid paddings across
// `apps/app/lib` (docs/research/2026-11-design-ux/typography-system.md §2).
// Fixing them all at once is a redesign; letting the number grow is how it
// got there. So this counts three things per file against a committed
// baseline, and the baseline may only go DOWN:
//
//   fontSize   a `fontSize:` outside the theme — a size no role owns
//   textStyle  a bare `TextStyle(` — a style built beside the theme, not from it
//   offGrid    an `EdgeInsets…(…)` or gap `SizedBox(width|height: n)` literal
//              off the 4-pt grid (0, 0.5, 1 and 2 are hairlines/half steps)
//
// Out of scope: `lib/src/theme/**` (where the scale lives), generated
// `*.g.dart`, and the print exporters `*_pdf.dart` / `*_docx.dart`, whose
// sizes are paper points, not screen roles.
//
//   npm run check:typography               fail on a count above the baseline,
//                                          or a baseline that is now too high
//   npm run check:typography -- --update   write the lower counts (never higher)
import {
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
  existsSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(here, "../..");
const LIB = join(REPO, "apps/app/lib");
const BASELINE = join(here, "typography-baseline.json");
const KINDS = ["fontSize", "textStyle", "offGrid"];

const excluded = (rel) =>
  rel.startsWith("apps/app/lib/src/theme/") ||
  rel.endsWith(".g.dart") ||
  rel.endsWith("_pdf.dart") ||
  rel.endsWith("_docx.dart");

function dartFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...dartFiles(full));
    else if (entry.endsWith(".dart")) out.push(full);
  }
  return out;
}

/** The line without its comment: whole-line comments vanish, a trailing
 * `// …` is cut when it is not inside a string literal. */
function code(line) {
  if (/^\s*(\/\/|\*|\/\*)/.test(line)) return "";
  let quote = null;
  for (let i = 0; i < line.length - 1; i++) {
    const c = line[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = null;
    } else if (c === "'" || c === '"') quote = c;
    else if (c === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

const NUMBER = /(?<![\w.$])(\d+(?:\.\d+)?)(?![\w.])/g;
const onGrid = (n) => n === 0 || n === 0.5 || n === 1 || n === 2 || n % 4 === 0;

/** The argument text of the call whose `(` is at `open`, up to its `)`. */
function args(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === "(") depth++;
    else if (text[i] === ")" && --depth === 0) return text.slice(open + 1, i);
  }
  return text.slice(open + 1);
}

/** Every finding in one file: [{kind, line, text}]. */
export function scan(source) {
  const lines = source.split("\n").map(code);
  const text = lines.join("\n");
  const lineAt = (index) => text.slice(0, index).split("\n").length;
  const found = [];
  for (const m of text.matchAll(/(?<![\w.])fontSize\s*:/g)) {
    found.push({ kind: "fontSize", line: lineAt(m.index) });
  }
  for (const m of text.matchAll(/(?<![\w.])TextStyle\s*\(/g)) {
    found.push({ kind: "textStyle", line: lineAt(m.index) });
  }
  const spacing = [
    /(?<![\w.])EdgeInsets(?:Directional)?\.(?:all|symmetric|only|fromLTRB|fromSTEB)\s*\(/g,
    /(?<![\w.])SizedBox\s*\(\s*(?=(?:width|height)\s*:\s*[\d.]+\s*,?\s*\))/g,
  ];
  for (const re of spacing) {
    for (const m of text.matchAll(re)) {
      const open = m.index + m[0].lastIndexOf("(");
      for (const n of args(text, open).matchAll(NUMBER)) {
        if (!onGrid(Number(n[1]))) {
          found.push({ kind: "offGrid", line: lineAt(m.index), value: n[1] });
        }
      }
    }
  }
  return found;
}

function measure() {
  const files = {};
  for (const full of dartFiles(LIB)) {
    const rel = relative(REPO, full).split("\\").join("/");
    if (excluded(rel)) continue;
    const found = scan(readFileSync(full, "utf8"));
    if (found.length === 0) continue;
    const counts = Object.fromEntries(KINDS.map((k) => [k, 0]));
    for (const f of found) counts[f.kind]++;
    files[rel] = { counts, found };
  }
  return files;
}

const totals = (entries) =>
  Object.fromEntries(
    KINDS.map((k) => [
      k,
      entries.reduce((sum, counts) => sum + (counts[k] ?? 0), 0),
    ]),
  );

function readBaseline() {
  if (!existsSync(BASELINE)) return null;
  return JSON.parse(readFileSync(BASELINE, "utf8")).files ?? {};
}

const now = measure();
const base = readBaseline();
const update = process.argv.includes("--update");

const over = [];
const stale = [];
const paths = new Set([...Object.keys(now), ...Object.keys(base ?? {})]);
for (const path of [...paths].sort()) {
  const counts = now[path]?.counts ?? {};
  const allowed = base?.[path] ?? {};
  for (const kind of KINDS) {
    const n = counts[kind] ?? 0;
    const max = allowed[kind] ?? 0;
    if (n > max) {
      const where = now[path].found
        .filter((f) => f.kind === kind)
        .map((f) => `${f.line}${f.value ? ` (${f.value})` : ""}`)
        .join(", ");
      over.push(`  ${path}  ${kind} ${n} > ${max}  — line ${where}`);
    } else if (n < max) {
      stale.push(`  ${path}  ${kind} ${n} < ${max}`);
    }
  }
}

if (update) {
  if (base && over.length > 0) {
    console.error(
      "✗ typography: the baseline only goes down — these counts went up:\n\n" +
        over.join("\n") +
        "\n\n  Use a textTheme role or `context.awText.*`, an AwSpace step, then re-run.",
    );
    process.exit(1);
  }
  const files = Object.fromEntries(
    Object.keys(now)
      .sort()
      .map((p) => [p, now[p].counts]),
  );
  const out = {
    note: "OPH-399 / ADR-0063 #5: counts may only go down. Regenerate with `npm run check:typography -- --update`.",
    total: totals(Object.values(files)),
    files,
  };
  writeFileSync(BASELINE, `${JSON.stringify(out, null, 2)}\n`);
  console.log(`✓ typography: baseline written — ${JSON.stringify(out.total)}`);
  process.exit(0);
}

if (base === null) {
  console.error(
    "✗ typography: no baseline — run `npm run check:typography -- --update` once.",
  );
  process.exit(1);
}

if (over.length > 0) {
  console.error(
    `✗ typography: ${over.length} count(s) above the baseline in apps/app/lib.\n\n` +
      over.join("\n") +
      "\n\n  DESIGN §3.3 / ADR-0063: sizes, weights and tracking come from the theme —\n" +
      "  a textTheme role or `context.awText.*` (sectionLabel, meta, rowTitle, numeric),\n" +
      "  spacing from AwSpace (4-pt grid). The baseline in scripts/design/\n" +
      "  typography-baseline.json may only go down.",
  );
  process.exit(1);
}

if (stale.length > 0) {
  console.error(
    "✗ typography: fewer raw styles than the baseline allows — lock the gain in:\n\n" +
      stale.join("\n") +
      "\n\n  npm run check:typography -- --update",
  );
  process.exit(1);
}

const total = totals(Object.values(now).map((f) => f.counts));
console.log(
  `✓ typography: at the baseline — fontSize ${total.fontSize}, TextStyle ${total.textStyle}, off-grid ${total.offGrid}`,
);
