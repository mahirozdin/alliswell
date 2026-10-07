#!/usr/bin/env node
// UI-AUDIT #44 / #63 — every word the EE server sends the app as a KEY has a sentence here.
//
// The server owns three closed vocabularies the app renders as words: webhook event classes
// (`ee.webhooks.event.<class>`), audit record kinds (`ee.audit.entity.<type>`) and audit verbs
// (`ee.verb.<verb>`). The app falls back to the wire name for a word it has none for, so a new
// server word shows up raw ("report.savedView") with every suite green. This check reads the
// server's own lists and fails on a missing label in either language — and on an audit kind the
// app's filter offers that the server no longer accepts (a 400 on tap).
//
// The EE overlay is private and optional (ee/ is gitignored): without it there is nothing to
// compare, and the check says so instead of failing a core-only checkout.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const ee = resolve(root, 'ee/server/modules');
const sources = {
  events: resolve(ee, 'notifications/event-routes.js'),
  audit: resolve(ee, 'audit/query.js'),
  verbs: resolve(ee, 'audit/verbs.js'),
};

if (!Object.values(sources).every((file) => existsSync(file))) {
  console.log('✓ i18n ee-vocabulary: no EE overlay checked out — nothing to compare');
  process.exit(0);
}

const load = (file) => import(pathToFileURL(file).href);
const { EVENT_CLASSES } = await load(sources.events);
const { HISTORY_ENTITY_TYPES } = await load(sources.audit);
const { AUDIT_VERBS } = await load(sources.verbs);

const languages = ['en', 'tr'];
const dictionaries = Object.fromEntries(
  languages.map((lang) => [
    lang,
    JSON.parse(readFileSync(resolve(root, `apps/app/assets/i18n/${lang}.json`), 'utf8')),
  ]),
);
const lookup = (dict, key) => key.split('.').reduce((node, part) => node?.[part], dict);

const problems = [];
const expectLabels = (prefix, words) => {
  for (const word of words) {
    for (const lang of languages) {
      if (typeof lookup(dictionaries[lang], `${prefix}.${word}`) !== 'string') {
        problems.push(`${lang}.json has no "${prefix}.${word}"`);
      }
    }
  }
};
expectLabels('ee.webhooks.event', EVENT_CLASSES);
expectLabels('ee.audit.entity', HISTORY_ENTITY_TYPES);
expectLabels('ee.verb', AUDIT_VERBS);

// The audit filter's kinds must be ones the server's querystring enum accepts.
const screen = readFileSync(
  resolve(root, 'apps/app/lib/src/features/ee/ui/audit_log_screen.dart'),
  'utf8',
);
const offered = screen.match(/const kEeAuditEntityTypes = <String>\[([\s\S]*?)\];/);
if (!offered) {
  problems.push('audit_log_screen.dart: kEeAuditEntityTypes not found');
} else {
  const accepted = new Set(HISTORY_ENTITY_TYPES);
  for (const [, type] of offered[1].matchAll(/'([a-z_]+)'/g)) {
    if (!accepted.has(type)) problems.push(`audit filter offers "${type}", the server refuses it`);
  }
}

if (problems.length > 0) {
  console.error(`✗ i18n ee-vocabulary: ${problems.length} server word(s) without a label:`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log(
  `✓ i18n ee-vocabulary: ${EVENT_CLASSES.length} events, ${HISTORY_ENTITY_TYPES.length} ` +
    `audit kinds, ${AUDIT_VERBS.length} verbs named in ${languages.join('+')}`,
);
