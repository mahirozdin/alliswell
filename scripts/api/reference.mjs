#!/usr/bin/env node
// OPH-294 — render docs/openapi.json into the reference section of docs/API.md.
//
// The narrative sections of API.md (get a key, find your workspace, recipes,
// key lifecycle) are hand-written and stay hand-written: they are the part a
// person reads once, and prose is the right form for them. Everything between
// the markers below is COMPILED from the spec, because it is the part that
// rots — 81 paths, 113 operations, every one of them with parameters, a body
// schema, a response shape and a set of error codes that change whenever the
// route does.
//
// Usage:
//   node scripts/api/reference.mjs           # rewrite the block in docs/API.md
//   node scripts/api/reference.mjs --check   # exit 1 if it would change
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

import { typeOf, constraintsOf, exampleFor, statusMeaning } from './lib/schema.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '../..');
const SPEC = join(ROOT, 'docs/openapi.json');
const DOC = join(ROOT, 'docs/API.md');

const BEGIN = '<!-- BEGIN GENERATED REFERENCE -->';
const END = '<!-- END GENERATED REFERENCE -->';

const spec = JSON.parse(readFileSync(SPEC, 'utf8'));

const METHOD_ORDER = ['get', 'post', 'put', 'patch', 'delete'];

/** A stable anchor for an operation, so the table of contents can link it. */
const anchor = (method, path) =>
  `${method}-${path}`
    .toLowerCase()
    .replace(/[{}]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');

const json = (value) => JSON.stringify(value, null, 2);

/** Markdown tables end a cell at `|`, and a `pattern` constraint is full of them. */
const escape = (s) => String(s).replace(/\|/g, '\\|').replace(/\n+/g, ' ').trim();

function propertyRows(schema, { required = [] } = {}) {
  const props = schema?.properties ?? {};
  const names = Object.keys(props);
  if (names.length === 0) return null;

  const lines = ['| Field | Type | Required | Notes |', '| --- | --- | --- | --- |'];
  for (const name of names) {
    const p = props[name];
    const notes = [constraintsOf(p), p.description ? escape(p.description) : '']
      .filter(Boolean)
      .join(' — ');
    lines.push(
      `| \`${name}\` | ${escape(typeOf(p))} | ${
        required.includes(name) ? '**yes**' : 'no'
      } | ${notes || '—'} |`,
    );
  }
  return lines.join('\n');
}

/** `curl` a reader can paste, with the placeholders spelled out. */
function curlFor(method, path, operation, bodyExample) {
  // Path placeholders stay visible as :name so it is obvious what to substitute.
  const url = `https://api.alliswell.space${path.replace(/\{(.+?)\}/g, ':$1')}`;
  const usesKey = (operation.security ?? []).some((s) => 'apiKey' in s);
  const token = usesKey ? '$ALLISWELL_KEY' : '$ALLISWELL_JWT';

  const lines = [`curl -X ${method.toUpperCase()} '${url}' \\`];
  if ((operation.security ?? []).length > 0) {
    lines.push(`  -H "Authorization: Bearer ${token}" \\`);
  }
  if (bodyExample !== null && bodyExample !== undefined) {
    lines.push("  -H 'Content-Type: application/json' \\");
    lines.push(`  -d '${JSON.stringify(bodyExample)}'`);
  } else {
    lines[lines.length - 1] = lines[lines.length - 1].replace(/ \\$/, '');
  }
  return lines.join('\n');
}

function renderOperation(method, path, operation) {
  const out = [];
  const params = operation.parameters ?? [];
  const pathParams = params.filter((p) => p.in === 'path');
  const queryParams = params.filter((p) => p.in === 'query');

  out.push(`#### \`${method.toUpperCase()} ${path}\``);
  out.push('');
  if (operation.summary) out.push(escape(operation.summary), '');

  const auth = (operation.security ?? []).length === 0
    ? 'None — this endpoint is public.'
    : (operation.security ?? []).some((s) => 'apiKey' in s)
      ? 'Personal API key **or** session JWT.'
      : 'Session JWT only — an API key is refused with `403 AUTH_APIKEY_FORBIDDEN`.';
  out.push(`**Auth:** ${auth}`, '');

  if (pathParams.length > 0) {
    out.push('**Path parameters**', '');
    out.push('| Name | Type | Notes |', '| --- | --- | --- |');
    for (const p of pathParams) {
      out.push(
        `| \`${p.name}\` | ${escape(typeOf(p.schema))} | ${constraintsOf(p.schema) || '—'} |`,
      );
    }
    out.push('');
  }

  if (queryParams.length > 0) {
    out.push('**Query parameters**', '');
    out.push('| Name | Type | Required | Notes |', '| --- | --- | --- | --- |');
    for (const p of queryParams) {
      out.push(
        `| \`${p.name}\` | ${escape(typeOf(p.schema))} | ${p.required ? 'yes' : 'no'} | ${constraintsOf(p.schema) || '—'} |`,
      );
    }
    out.push('');
  }

  const bodySchema = operation.requestBody?.content?.['application/json']?.schema;
  let bodyExample = null;
  if (bodySchema) {
    const rows = propertyRows(bodySchema, { required: bodySchema.required ?? [] });
    if (rows) out.push('**Request body**', '', rows, '');
    // The SHORTEST body that works — what a reader actually copies.
    bodyExample = exampleFor(bodySchema, { requiredOnly: true });
  }

  out.push('**Request**', '', '```bash', curlFor(method, path, operation, bodyExample), '```', '');

  const responses = Object.entries(operation.responses ?? {}).sort(([a], [b]) =>
    a.localeCompare(b),
  );
  if (responses.length > 0) {
    out.push('**Responses**', '');
    out.push('| Status | Meaning |', '| --- | --- |');
    for (const [status, response] of responses) {
      out.push(`| \`${status}\` | ${escape(statusMeaning(status, response.description))} |`);
    }
    out.push('');

    const ok = responses.find(([status]) => status.startsWith('2'));
    const okSchema = ok?.[1]?.content?.['application/json']?.schema;
    if (okSchema) {
      const example = exampleFor(okSchema);
      if (example !== null) {
        out.push(`**Example response** (\`${ok[0]}\`)`, '', '```json', json(example), '```', '');
      }
    }
  }

  return out.join('\n');
}

function render() {
  const byTag = new Map();
  for (const [path, methods] of Object.entries(spec.paths)) {
    for (const method of METHOD_ORDER) {
      const operation = methods[method];
      if (!operation) continue;
      const tag = operation.tags?.[0] ?? 'Other';
      if (!byTag.has(tag)) byTag.set(tag, []);
      byTag.get(tag).push({ method, path, operation });
    }
  }

  const tags = [...byTag.keys()].sort();
  const out = [BEGIN, ''];

  const opCount = [...byTag.values()].reduce((n, list) => n + list.length, 0);
  out.push(
    `_${opCount} operations across ${Object.keys(spec.paths).length} paths, generated from`,
    "[`openapi.json`](openapi.json) — which is itself generated from the server's own",
    'route schemas. Do not edit this section by hand; run `npm run api:docs`._',
    '',
  );

  out.push('**Contents**', '');
  for (const tag of tags) {
    const links = byTag
      .get(tag)
      .map(
        ({ method, path }) =>
          `[\`${method.toUpperCase()} ${path}\`](#${anchor(method, path)})`,
      )
      .join(' · ');
    out.push(`- **${tag}** — ${links}`);
  }
  out.push('');

  for (const tag of tags) {
    out.push(`### ${tag}`, '');
    for (const { method, path, operation } of byTag.get(tag)) {
      out.push(renderOperation(method, path, operation), '');
    }
  }

  out.push(END);
  return out.join('\n');
}

const block = render();
const doc = readFileSync(DOC, 'utf8');

const start = doc.indexOf(BEGIN);
const end = doc.indexOf(END);
if (start === -1 || end === -1) {
  console.error(`docs/API.md is missing the ${BEGIN} / ${END} markers.`);
  process.exit(1);
}

const next = `${doc.slice(0, start)}${block}${doc.slice(end + END.length)}`;

if (process.argv.includes('--check')) {
  if (next !== doc) {
    console.error('The generated reference in docs/API.md is out of date.');
    console.error('Run: npm run api:docs   (and commit the result)');
    process.exit(1);
  }
  console.log('check:apidocs — the reference matches the spec.');
} else {
  writeFileSync(DOC, next);
  console.log(`Rewrote the reference block in docs/API.md.`);
}
