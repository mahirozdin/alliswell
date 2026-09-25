#!/usr/bin/env node
// OPH-332 — every searchable entity has a way in.
//
// ── THE RULE THIS ENFORCES WAS ALREADY WRITTEN ────────────────────────
//
// OPH-326 built the search registry and wrote its own stake: "an entity left
// out of search is an entity that does not exist for the user." The registry
// kept that promise — register an entity, get folded shadow columns, get the
// SQL. What nothing checked was the other end: whether any SCREEN ever asks.
//
// Measured in the EE-196 round and again in EE-220: `searchChanges`,
// `searchProblems` and `searchAssets` had ZERO callers. Three entities were
// registered, indexed, pulled to every device — and unreachable. The registry
// was green the whole time, because the registry is not where the gap lives.
//
// ── WHY A GATE RATHER THAN A CAREFUL REVIEW ───────────────────────────
//
// This is the failure mode a review cannot catch: nothing is broken, no test
// is red, and the missing thing is an ABSENCE in a file nobody opened. It
// went unnoticed across four rounds. `check:opacity` exists for the same
// reason — "the layer the gate could not see".
//
// Checked in BOTH directions, like rule 12's MCP check:
//
//   registered-but-uncalled   an entity the user cannot search for
//   called-but-unregistered   a method that survived its entity's removal
//
// An entity with no caller may be EXEMPT, but only with a reason written in
// EXEMPT below. A gate that can be silenced by editing a list is fine; one
// that can be silenced without saying why is not.
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const APP = resolve(here, '../../apps/app/lib');
const REGISTRY = join(APP, 'src', 'search', 'search.dart');

/**
 * Entities that may have no caller, and why. EE-220's own acceptance allows
 * this — "or its absence recorded in a written decision" — and this is that
 * record. Doing neither is not a third option.
 */
const EXEMPT = {
  problems:
    'EE-188, same shape as changes: no screen in the app, so no caller can ' +
    'exist. Recorded here so the next round finds a decision instead of a gap.',
};

const failures = [];
const src = readFileSync(REGISTRY, 'utf8');

// `const _assets = SearchEntity(` — the registry's own declaration form.
const entities = [...src.matchAll(/const\s+_([A-Za-z0-9]+)\s*=\s*SearchEntity\(/g)].map(
  (m) => m[1],
);
if (entities.length === 0) {
  // A gate passing on an empty set is the oldest way to ship nothing. If the
  // registry is ever restructured past this pattern, that must be loud.
  failures.push(
    'check:search-reachable: no SearchEntity found in search.dart — the gate is ' +
      'passing on an empty set',
  );
}

/** `_kbArticles` → `searchKbArticles`. The registry names them in lockstep. */
const methodFor = (entity) => `search${entity[0].toUpperCase()}${entity.slice(1)}`;

const dartFiles = [];
(function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.dart') && !entry.name.endsWith('.g.dart')) {
      dartFiles.push(full);
    }
  }
})(APP);

// A caller is anything outside `search.dart` ITSELF. The exclusion is that
// narrow on purpose, and it was calibrated by measurement: excluding the whole
// `src/search/` folder made the gate report tasks, events and projects as
// unreachable, when in fact `src/search/providers.dart` — the global search
// screen's own providers — is exactly the kind of caller this gate is looking
// for. Only the file that DECLARES the methods is not a caller of them.
const DECLARES = `${sep}src${sep}search${sep}search.dart`;
const callers = new Map();
for (const file of dartFiles) {
  if (file.endsWith(DECLARES)) continue;
  const body = readFileSync(file, 'utf8');
  for (const m of body.matchAll(/\.(search[A-Z][A-Za-z0-9]*)\(/g)) {
    if (!callers.has(m[1])) callers.set(m[1], []);
    callers.get(m[1]).push(file.slice(APP.length + 1));
  }
}

for (const entity of entities) {
  const method = methodFor(entity);
  if (!src.includes(`${method}(`)) {
    failures.push(
      `search.dart: "_${entity}" is registered but there is no ${method}() to call — ` +
        'the registry and the service have drifted apart',
    );
    continue;
  }
  const seen = callers.get(method) ?? [];
  if (seen.length > 0) {
    // OPH-348: the other half of "an exemption for an entity that no longer
    // exists". An exemption says why nothing calls this; the day a screen
    // does, that sentence is false — and a gate that kept carrying it green
    // would be the place the NEXT real absence hides, behind a reason nobody
    // reads any more. Measured: `changes` gained its screen and this loop
    // walked straight past its "the app has no change screen" line.
    if (EXEMPT[entity]) {
      failures.push(
        `EXEMPT lists "${entity}" but ${method}() is called from ${seen[0]} — ` +
          'the reason is stale; delete the exemption',
      );
    }
    continue;
  }
  if (EXEMPT[entity]) continue;
  failures.push(
    `${method}() has no caller in apps/app/lib — OPH-326: an entity left out of ` +
      'search does not exist for the user. Add a caller, or add an entry to ' +
      'EXEMPT in this file with the reason.',
  );
}

// The other direction: a method somebody still calls whose entity is gone.
for (const [method, files] of callers) {
  const known = entities.some((e) => methodFor(e) === method);
  if (known) continue;
  failures.push(
    `${method}() is called from ${files[0]} but no SearchEntity declares it — ` +
      'a screen is asking for something the registry no longer knows',
  );
}

// An exemption for an entity that no longer exists is a reason nobody reads.
for (const entity of Object.keys(EXEMPT)) {
  if (entities.includes(entity)) continue;
  failures.push(
    `EXEMPT lists "${entity}" but the registry has no such entity — a stale ` +
      'exemption hides the next real one',
  );
}

if (failures.length > 0) {
  console.error(`✗ search reachable: ${failures.length} problem:\n`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
const exempt = Object.keys(EXEMPT).length;
console.log(
  `✓ search reachable: ${entities.length} entity, ` +
    `${entities.length - exempt} of them reached from a screen, ` +
    `${exempt} exempt with a written reason, no orphan callers`,
);
