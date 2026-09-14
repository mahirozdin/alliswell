#!/usr/bin/env node
// OPH-302 — fail CI on an `Opacity` wrapper in the app's own widgets.
//
// DESIGN §20 C3 already says it: *"Calm is built from tokens, never from
// `Opacity`."* The reason is measurable rather than aesthetic — `contrast.py`
// compares COLOUR PAIRS, and an opacity layer is not a colour. Whatever sits
// under one is invisible to the gate, so `FAILURES: 0` keeps printing while
// the text underneath falls through the floor.
//
// It did. Three wrappers shipped: the selected-day dim on task rows and event
// rows (0.45 → **2.13:1** for variant text on white, against a 4.5:1 floor) and
// an inactive team member (0.55 → 2.63:1). Nobody reported the third one, which
// is the whole argument for a mechanical check: the rule was written, the
// reason was written, and three call sites broke it anyway.
//
// Measured while writing this gate, and the reason the fix could not simply be
// "use a higher alpha": holding 4.5:1 for `onSurfaceVariant` on white needs
// **α ≥ 0.79**. There is no alpha that both reads as dimmed and stays legible,
// so de-emphasis has to move off the text and onto the container.
//
// Escape hatch for a genuine exception: `// opacity-ok: <reason>` on the line
// above. DESIGN §22 Q4b is the worked example of when that is legitimate — a
// named exception with its own contrast argument, not a shrug.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const LIB = resolve(here, '../../apps/app/lib');
const CWD = process.cwd();

// Every widget that puts a layer between the text and the gate. `Animated` and
// `Sliver` are in the list deliberately: a rule with a synonym its author can
// reach for instead is not a rule, and the one sanctioned exception in the app
// (§22 Q4b's receded quick-access button) is an `AnimatedOpacity` — it should
// have to SAY it is the exception, not slip through on a spelling.
const PATTERN = /(?<![A-Za-z.])(Animated|Sliver)?Opacity\s*\(/;
const ALLOW = /\/\/\s*opacity-ok:/;

function dartFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...dartFiles(full));
    else if (entry.endsWith('.dart')) out.push(full);
  }
  return out;
}

const isComment = (line) => /^\s*(\/\/|\*|\/\*)/.test(line);

/**
 * Is this call site exempted?
 *
 * The marker may sit anywhere in the contiguous comment block directly above,
 * because a reason worth writing rarely fits on one line — and a gate that
 * forced it to would be teaching people to write worse reasons.
 */
function exempt(lines, i) {
  if (ALLOW.test(lines[i])) return true;
  for (let j = i - 1; j >= 0 && isComment(lines[j]); j--) {
    if (ALLOW.test(lines[j])) return true;
  }
  return false;
}

const violations = [];
for (const file of dartFiles(LIB)) {
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    // Prose is not code. This file, and the tokens that replaced the wrappers,
    // both have to be able to SAY `Opacity(` while explaining why they do not
    // use one — a gate that fires on its own rationale gets switched off.
    if (isComment(line)) return;
    if (!PATTERN.test(line)) return;
    if (exempt(lines, i)) return;
    violations.push(`${relative(CWD, file)}:${i + 1}  ${line.trim()}`);
  });
}

if (violations.length > 0) {
  console.error(
    `✗ opacity: ${violations.length} \`Opacity\` wrapper(s) in apps/app/lib.\n\n` +
      violations.map((v) => `  ${v}`).join('\n') +
      '\n\n  DESIGN §20 C3: calm is built from TOKENS, never from `Opacity` —\n' +
      '  an opacity layer is not a colour, so scripts/design/contrast.py cannot\n' +
      '  see through it and its `FAILURES: 0` stops meaning anything.\n' +
      '  Blend the colour instead (Color.alphaBlend) and register the pair, or\n' +
      '  mark a genuine exception with `// opacity-ok: <reason>` above the line.',
  );
  process.exit(1);
}

console.log('✓ opacity: no unmeasurable opacity layers in apps/app/lib');
