#!/usr/bin/env node
// OPH-127 — fail CI on new hardcoded user-facing strings in the Flutter app.
// Every label must go through the i18n facade: `'some.key'.tr()`. This mirrors
// the TypeScript-ban guard (`check:no-ts`) and keeps the OPH-122…124 extraction
// from rotting. Escape hatch for a genuine exception: append `// i18n-ignore`.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const LIB = resolve(here, '../../apps/app/lib');
const CWD = process.cwd();

// Skip lines that already localize, opt out explicitly, or name the brand.
const ALLOW = [/\.tr\(/, /i18n-ignore/, /'AllisWell'/, /"AllisWell"/];

// A user-facing string literal is a quote followed by a LETTER (so `'$var'`
// interpolation and `'edit'`-style enum/action values in non-label positions
// are not swept in). We only look at widget/label positions.
const PATTERNS = [
  /\bText\(\s*['"][A-Za-z]/,
  /\b(labelText|hintText|helperText|tooltip|placeholder|semanticLabel)\s*:\s*['"][A-Za-z]/,
];

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
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (ALLOW.some((re) => re.test(line))) return;
    if (PATTERNS.some((re) => re.test(line))) {
      violations.push({ file: relative(CWD, file), line: i + 1, text: line.trim() });
    }
  });
}

if (violations.length > 0) {
  console.error(
    `✗ i18n: ${violations.length} hardcoded user-facing string(s). ` +
      `Wrap each in '<key>'.tr() (add the key to assets/i18n/*.json), ` +
      `or append // i18n-ignore if it is genuinely not translatable:\n`,
  );
  for (const v of violations) console.error(`  ${v.file}:${v.line}\n    ${v.text}`);
  process.exit(1);
}
console.log('✓ i18n: no hardcoded user-facing strings in apps/app/lib');
