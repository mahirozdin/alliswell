import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, test } from 'vitest';

import en from '../../../landing/src/content.js';
import tr from '../../../landing/src/content.tr.js';

/// OPH-412 (polish 3, M-2) — the self-hosting claim says what the install is.
///
/// The homepage promised "Your server, one command." beside a README whose
/// "Run it yourself" block is six lines: two downloads, two generated secrets,
/// an edit of .env, then the compose command. A self-hoster who reads both
/// trusts neither. The section now names the four steps and labels the
/// command it shows as the last one; the README's summary lines stop saying
/// "one docker compose up" too.

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const README = readFileSync(join(ROOT, 'README.md'), 'utf8');

/** The bash block under "## Run it yourself": the install as the README gives it. */
function readmeInstall() {
  const section = README.slice(README.indexOf('## Run it yourself'));
  const block = section.match(/```bash\n([\s\S]*?)```/)[1];
  return block
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);
}

describe('the homepage section claims the install the README gives', () => {
  test('no "one command" in the title, in either language', () => {
    expect(en.own.title).not.toMatch(/one command/i);
    expect(tr.own.title).not.toMatch(/tek komut/i);
    expect(en.own.title).toBe('Your server, four steps.');
    expect(tr.own.title).toBe('Kendi sunucunuzda, dört adımda.');
  });

  test('the README block is still the four steps the lead names', () => {
    const lines = readmeInstall();
    // 1. two downloads: the compose file and the .env template
    expect(lines.filter((l) => l.startsWith('curl '))).toHaveLength(2);
    // 2. two generated secrets
    expect(lines.filter((l) => /SECRET=\$\(openssl rand/.test(l))).toHaveLength(2);
    // 3. the domains and database passwords, by hand
    expect(lines.some((l) => /^nano \.env\b.*domains.*passwords/.test(l))).toBe(true);
    // 4. the command the section shows, last
    expect(lines.at(-1)).toBe(en.own.command);
    expect(tr.own.command).toBe(en.own.command);
  });

  test('the lead names each step, and the command is labelled as the last one', () => {
    expect(en.own.lead).toMatch(
      /^Two files, two secrets, your domains and passwords, one command\./,
    );
    expect(en.own.commandLabel).toBe('Last step');
    // `/i` does not fold the Turkish dotted capital, so the sentence is spelled out.
    expect(tr.own.lead).toMatch(
      /^İki dosya, iki gizli anahtar, alan adlarınız ve şifreleriniz, tek komut\./,
    );
    expect(tr.own.commandLabel).toBe('Son adım');
  });
});

describe('the README summary lines stop promising a single command', () => {
  test('no "one docker compose up" claim outside the install block', () => {
    expect(README).not.toMatch(/\b[Oo]ne `docker compose up`/);
  });
});
