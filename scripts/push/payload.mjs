#!/usr/bin/env node
/**
 * OPH-308 — nothing a task says may cross a push provider.
 *
 * `docs/PRIVACY.md` tells users that their task titles and contents are never
 * sent to Apple's, Google's or anyone else's push service, and BLUEPRINT §8.3
 * says the same thing to us. A promise like that is kept by a narrow place, not
 * by care: `apps/api/src/lib/push/payload.js` is the only builder of a push
 * body, and this gate is what notices when its shape changes.
 *
 * ── WHY AN ALLOWLIST AND NOT A GENERATED FIXTURE ──────────────────────────
 *
 * A fixture generated from the code and then compared against the code proves
 * nothing — it is the failure mode the repo already named: *a gate that reads
 * what it does not measure the same as green is not a gate.* So the two sides
 * here are POLICY and CODE, the shape `scripts/android/allowed-permissions.txt`
 * established: the text file is what a human agreed may be sent, this script
 * reads what the code would actually send, and any difference stops the build.
 * Adding a key stays possible and stops being quiet.
 *
 *   node scripts/push/payload.mjs           # check (CI)
 *   node scripts/push/payload.mjs --write   # accept a deliberate change
 *
 * ── AND A SECOND, INDEPENDENT QUESTION ────────────────────────────────────
 *
 * The key set is the obvious leak. The quiet one is a declared key holding
 * prose, so this also builds every payload beside a task whose every field is
 * a sentence and reads the wire format back: if any of it appears, the gate
 * fails for a different reason and says which. That check does not depend on
 * the allowlist being right.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import {
  PUSH_ALERT_IDS,
  PUSH_PAYLOAD_KEYS,
  buildReminderPayload,
  buildWakePayload,
} from '../../apps/api/src/lib/push/payload.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const ALLOWLIST = resolve(ROOT, 'scripts/push/allowed-payload-keys.txt');

/** A task whose every field is something a person would not want broadcast. */
const LOUD_TASK = {
  id: '01HZTASKAAAAAAAAAAAAAAAAAA',
  title: 'Ameliyat sonucu — Dr. Yılmaz',
  description: 'biopsy results, call the clinic',
  notes: 'SECRET',
};
const LOUD_FRAGMENTS = [
  LOUD_TASK.title,
  LOUD_TASK.description,
  LOUD_TASK.notes,
  'Yılmaz',
  'biopsy',
  'SECRET',
];

/**
 * Every payload the code can produce, built the way a careless call site
 * would: the whole task spread in, in the hope the builder passes it on.
 */
function samples() {
  const common = {
    ...LOUD_TASK,
    reminderId: '01HZRMNDRAAAAAAAAAAAAAAAAA',
    taskId: LOUD_TASK.id,
    fireAt: '2026-09-20T07:30:00.000Z',
  };
  return [
    buildWakePayload(),
    buildReminderPayload(common),
    ...PUSH_ALERT_IDS.map((alert) => buildReminderPayload({ ...common, alert })),
  ];
}

/** What the code would send, as sorted `type.key` and `alert:id` lines. */
function actual() {
  const lines = new Set();
  for (const [type, keys] of Object.entries(PUSH_PAYLOAD_KEYS)) {
    for (const key of keys) lines.add(`${type}.${key}`);
  }
  for (const id of PUSH_ALERT_IDS) lines.add(`alert:${id}`);
  // Declared and emitted are checked together on purpose: a key the builders
  // emit but nobody declared is as much a change as the other way round.
  for (const payload of samples()) {
    for (const key of Object.keys(payload)) lines.add(`${payload.type}.${key}`);
  }
  return [...lines].sort();
}

/** @returns {string[]} the fragments that reached the wire, if any. */
function leaks() {
  const found = new Set();
  for (const payload of samples()) {
    const wire = JSON.stringify(payload);
    for (const fragment of LOUD_FRAGMENTS) {
      if (wire.includes(fragment)) found.add(fragment);
    }
  }
  return [...found];
}

const lines = actual();
const leaked = leaks();

if (leaked.length > 0) {
  console.error(
    '✗ push payload: a task field reached the wire.\n' +
      leaked.map((f) => `    ${JSON.stringify(f)}`).join('\n') +
      '\n\n  This is not a formality. docs/PRIVACY.md tells users that their task\n' +
      '  titles and contents never reach a push provider, and BLUEPRINT §8.3 is\n' +
      '  the rule behind that sentence. Whatever put this on the wire has to go —\n' +
      '  the device already has the text, so the payload names the row instead.',
  );
  process.exit(1);
}

if (process.argv.includes('--write')) {
  writeFileSync(ALLOWLIST, `${lines.join('\n')}\n`);
  console.log(`Wrote ${ALLOWLIST}:`);
  for (const line of lines) console.log(`  ${line}`);
  process.exit(0);
}

let allowed;
try {
  allowed = readFileSync(ALLOWLIST, 'utf8').split('\n').filter(Boolean);
} catch {
  console.error(
    `✗ push payload: ${ALLOWLIST} is missing — run \`npm run check:push-payload -- --write\`.`,
  );
  process.exit(1);
}

const added = lines.filter((l) => !allowed.includes(l));
const removed = allowed.filter((l) => !lines.includes(l));

if (added.length === 0 && removed.length === 0) {
  console.log(`✓ push payload: the contract is exactly the ${lines.length} agreed entries`);
} else {
  console.error(
    '✗ push payload: what a push would carry has changed.\n' +
      added.map((l) => `  + ${l}`).join('\n') +
      (added.length && removed.length ? '\n' : '') +
      removed.map((l) => `  - ${l}`).join('\n') +
      '\n\n  A "+" line is something new that would cross Apple\'s, Google\'s or\n' +
      "  Mozilla's servers. If it names a task — a title, a body, a note — it does\n" +
      '  not belong there: the device already has the text (BLUEPRINT §8.3,\n' +
      '  ADR-0038). If the change is intended, re-run with --write and say why in\n' +
      '  the commit.',
  );
  process.exit(1);
}
