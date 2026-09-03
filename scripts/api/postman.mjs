#!/usr/bin/env node
// OPH-297 — build the Postman collection from docs/openapi.json.
//
// Generated from the same spec as the reference, so the two physically cannot
// disagree. A hand-written collection would be a third copy of the route
// table, and the first two both drifted.
//
// Output lands in the landing site's `public/` directory, which Vite copies
// verbatim into the deployed docroot — so the file is downloadable at
// https://alliswell.space/downloads/alliswell.postman_collection.json with no
// server configuration at all.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

import { exampleFor } from './lib/schema.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '../..');
const SPEC = join(ROOT, 'docs/openapi.json');
const OUT_DIR = join(ROOT, 'apps/landing/public/downloads');
const OUT = join(OUT_DIR, 'alliswell.postman_collection.json');

const spec = JSON.parse(readFileSync(SPEC, 'utf8'));
const METHOD_ORDER = ['get', 'post', 'put', 'patch', 'delete'];

/**
 * A deterministic id, so regenerating an unchanged spec produces an unchanged
 * file. `crypto.randomUUID()` here would make every build a diff and the
 * drift check meaningless.
 */
const idFor = (s) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  const hex = h.toString(16).padStart(8, '0');
  return `${hex}-0000-4000-8000-${hex}00000000`.slice(0, 36);
};

/** `/api/v1/workspaces/{workspaceId}/tasks` → Postman's `:workspaceId` form. */
function toPostmanPath(path) {
  return path
    .split('/')
    .filter(Boolean)
    .map((segment) => {
      const m = segment.match(/^\{(.+)\}$/);
      if (!m) return segment;
      // The workspace id is the one path variable a reader has already been
      // told how to find (§2 of the reference), so it gets the collection
      // variable rather than an empty box.
      return m[1] === 'workspaceId' ? '{{workspaceId}}' : `:${m[1]}`;
    });
}

function requestFor(method, path, operation) {
  const segments = toPostmanPath(path);
  const query = (operation.parameters ?? [])
    .filter((p) => p.in === 'query')
    .map((p) => ({
      key: p.name,
      value: p.schema?.default !== undefined ? String(p.schema.default) : '',
      description: [p.description, p.required ? '(required)' : '']
        .filter(Boolean)
        .join(' '),
      disabled: !p.required,
    }));

  const variable = (operation.parameters ?? [])
    .filter((p) => p.in === 'path' && p.name !== 'workspaceId')
    .map((p) => ({ key: p.name, value: '', description: p.description ?? '' }));

  const header = [];
  const bodySchema = operation.requestBody?.content?.['application/json']?.schema;
  const request = {
    method: method.toUpperCase(),
    header,
    url: {
      raw: `{{baseUrl}}/${segments.join('/')}`,
      host: ['{{baseUrl}}'],
      path: segments,
      ...(query.length > 0 ? { query } : {}),
      ...(variable.length > 0 ? { variable } : {}),
    },
    description: operation.description ?? '',
  };

  if (bodySchema) {
    header.push({ key: 'Content-Type', value: 'application/json' });
    request.body = {
      mode: 'raw',
      raw: JSON.stringify(exampleFor(bodySchema, { requiredOnly: true }) ?? {}, null, 2),
      options: { raw: { language: 'json' } },
    };
  }

  // Auth: the collection carries the API key at the top level, so only the
  // exceptions are spelled out here — the JWT-only routes, which would
  // otherwise silently 403 and look like a broken collection.
  const security = operation.security ?? [];
  if (security.length === 0) {
    request.auth = { type: 'noauth' };
  } else if (!security.some((s) => 'apiKey' in s)) {
    request.auth = {
      type: 'bearer',
      bearer: [{ key: 'token', value: '{{sessionJwt}}', type: 'string' }],
    };
  }

  return request;
}

const folders = new Map();
for (const [path, methods] of Object.entries(spec.paths)) {
  for (const method of METHOD_ORDER) {
    const operation = methods[method];
    if (!operation) continue;
    const tag = operation.tags?.[0] ?? 'Other';
    if (!folders.has(tag)) folders.set(tag, []);
    folders.get(tag).push({
      name: operation.summary || `${method.toUpperCase()} ${path}`,
      request: requestFor(method, path, operation),
    });
  }
}

const collection = {
  info: {
    _postman_id: idFor('alliswell'),
    name: `AllisWell REST API v${spec.info.version}`,
    description:
      'Generated from the AllisWell OpenAPI spec — see ' +
      'https://alliswell.space/docs/api\n\n' +
      'Set `apiKey` to a personal key (Settings → API access and management) ' +
      'and `workspaceId` to the workspace it belongs to; `GET /api/v1/me` ' +
      'lists yours. The few endpoints a key may not open are marked and use ' +
      '`sessionJwt` instead.',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  auth: {
    type: 'bearer',
    bearer: [{ key: 'token', value: '{{apiKey}}', type: 'string' }],
  },
  variable: [
    { key: 'baseUrl', value: 'https://api.alliswell.space', type: 'string' },
    { key: 'apiKey', value: '', type: 'string' },
    { key: 'workspaceId', value: '', type: 'string' },
    { key: 'sessionJwt', value: '', type: 'string' },
  ],
  item: [...folders.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, items]) => ({ name, item: items })),
};

const json = `${JSON.stringify(collection, null, 2)}\n`;

if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(OUT, 'utf8');
  } catch {
    console.error('The Postman collection is missing. Run: npm run api:docs');
    process.exit(1);
  }
  if (current !== json) {
    console.error('The Postman collection is out of date. Run: npm run api:docs');
    process.exit(1);
  }
  console.log('check:postman — the collection matches the spec.');
} else {
  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT, json);
  const count = collection.item.reduce((n, f) => n + f.item.length, 0);
  console.log(`Wrote the Postman collection (${count} requests in ${collection.item.length} folders).`);
}
