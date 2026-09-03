#!/usr/bin/env node
// OPH-294 — generate docs/openapi.json from the routes themselves.
//
// Why generated rather than written: `docs/API.md` was written by hand beside
// the code and drifted, in ways nobody could see. It described a `409` body
// carrying `conflictVersionId` that the server has never sent (the route sets
// the property, and Fastify's error serializer drops it — the field only
// exists on the /sync/push path). It listed three route families closed to API
// keys when there are four; the self-credential family added by OPH-283/284
// was never written down. It documented 9 error codes out of ~90.
//
// None of that is carelessness — it is what happens to a 78-route reference
// maintained by hand. So the reference is compiled from the same Ajv schemas
// Fastify validates against, and `check:openapi` fails the build when the
// committed spec no longer matches the code.
//
// The app is built with stubbed infrastructure, exactly as the unit tests do
// it (`buildApp` documents this). Nothing connects, nothing listens; the
// process only needs the routes to REGISTER so their schemas can be read.
//
// Usage:
//   node scripts/api/openapi.mjs            # write docs/openapi.json
//   node scripts/api/openapi.mjs --check    # exit 1 if it would change
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import swagger from '@fastify/swagger';

import { buildApp } from '../../apps/api/src/app.js';
import { loadConfig } from '../../apps/api/src/config.js';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '../..');
const OUT = join(ROOT, 'docs/openapi.json');

const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));

/**
 * Surfaces this spec deliberately does NOT describe.
 *
 * - `/mcp` and `/oauth/*` + `/.well-known/*` are the MCP track (ADR-0022):
 *   JSON-RPC and an OAuth 2.1 authorization server, neither of which is a
 *   REST resource and neither of which a personal API key can open. They
 *   have their own document, docs/MCP.md.
 * - `/api/v1/ee/*` beyond `/ee/status` belongs to the enterprise overlay,
 *   which is a separate private repository (`check:no-ee`). A CE spec that
 *   described it would document routes this build does not have.
 */
const EXCLUDED = [/^\/mcp$/, /^\/oauth\//, /^\/\.well-known\//];

/** Ajv/Fastify JSON Schema is OpenAPI-compatible except in a few places. */
function toOpenApiSchema(node) {
  if (Array.isArray(node)) return node.map(toOpenApiSchema);
  if (!node || typeof node !== 'object') return node;

  const out = {};
  for (const [key, value] of Object.entries(node)) {
    // JSON Schema allows `type: ['string','null']`; OpenAPI 3.0 does not, and
    // 3.1 prefers it spelled out. Every nullable column in this API is
    // written the first way, so this is not an edge case — it is most of the
    // response schemas.
    if (key === 'type' && Array.isArray(value)) {
      const types = value.filter((t) => t !== 'null');
      out.type = types.length === 1 ? types[0] : types;
      if (value.includes('null')) out.nullable = true;
      continue;
    }
    out[key] = toOpenApiSchema(value);
  }
  return out;
}

/**
 * Doors closed to API keys by a PLUGIN-level hook rather than a route-level
 * one, which `onRoute` cannot see.
 *
 * `routes/ai.js` guards its whole scope with one `addHook`, deliberately: it
 * is "the one place a new /ai route cannot forget to opt in", and that safety
 * property is worth more than the convenience of static inspection. But a
 * spec that read only the route options would publish `/ai/*` as open to API
 * keys — the exact species of confident, invisible lie this generator exists
 * to stop. So the rule is stated here and checked against its source below:
 * if that hook ever moves, generation fails instead of quietly downgrading.
 */
const PLUGIN_LEVEL_CLOSED = [
  {
    match: /\/ai(\/|$)/,
    source: 'apps/api/src/routes/ai.js',
    evidence: "app.addHook('preHandler', app.rejectApiKeys)",
  },
];

function assertPluginLevelRulesStillHold() {
  for (const rule of PLUGIN_LEVEL_CLOSED) {
    const src = readFileSync(join(ROOT, rule.source), 'utf8');
    if (!src.includes(rule.evidence)) {
      throw new Error(
        `${rule.source} no longer contains ${rule.evidence}. The API-key rule ` +
          'for those routes changed; update PLUGIN_LEVEL_CLOSED in this script ' +
          'rather than shipping a spec that states the old one.',
      );
    }
  }
}

/**
 * Which credentials open a route.
 *
 * Read from the route's own hooks wherever possible, rather than from a list
 * kept here: a list is one more thing to forget, and forgetting it is exactly
 * how the hand-written reference came to describe three closed doors when
 * there are four.
 */
function securityFor(routeOptions, path) {
  const pre = [routeOptions.preHandler ?? []].flat();
  const onReq = [routeOptions.onRequest ?? []].flat();

  const authenticated = onReq.some((h) => h?.name === 'authenticate');
  if (!authenticated) return { security: [], note: 'No credentials required.' };

  const jwtOnly =
    pre.some((h) => h?.name === 'rejectApiKeys') ||
    PLUGIN_LEVEL_CLOSED.some((rule) => rule.match.test(path));
  if (jwtOnly) {
    return {
      security: [{ sessionJwt: [] }],
      note:
        'Session JWT only. A personal API key is refused here with ' +
        '`403 AUTH_APIKEY_FORBIDDEN` (ADR-0032 §4).',
    };
  }
  return {
    security: [{ sessionJwt: [] }, { apiKey: [] }],
    note: 'Accepts either a session JWT or a personal API key.',
  };
}

const TAG_RULES = [
  [/^\/health/, 'Health'],
  [/^\/api\/v1\/auth\//, 'Authentication'],
  [/api-keys/, 'API keys'],
  [/^\/api\/v1\/me/, 'Account'],
  [/tasks|checklist/, 'Tasks'],
  [/task-series/, 'Recurrence'],
  [/notes|versions/, 'Notes'],
  [/projects/, 'Projects'],
  [/tags/, 'Tags'],
  [/files|folders|storage/, 'Files'],
  [/quick-links/, 'Quick links'],
  [/reminders/, 'Reminders'],
  [/notification-devices/, 'Devices'],
  [/import|export/, 'Import & export'],
  [/sync/, 'Sync'],
  [/integrations\/google/, 'Google Calendar'],
  [/\/ai\/|\/ai$/, 'AI'],
  [/\/ee\//, 'Capabilities'],
];

function tagFor(url) {
  for (const [pattern, tag] of TAG_RULES) if (pattern.test(url)) return tag;
  return 'Service';
}

const stub = {
  db: { raw: async () => [[{ 1: 1 }]] },
  redis: { ping: async () => 'PONG' },
};

async function generate() {
  assertPluginLevelRulesStillHold();

  const config = loadConfig({
    NODE_ENV: 'test',
    // Document the whole CE surface, including the routes that are
    // conditionally registered — a reference that changed shape with one
    // deployment's feature flags would describe that deployment, not the
    // software. AI routes are documented AS JWT-only, which is the honest
    // answer for a reader holding an API key.
    AI_ENABLED: 'true',
    // MCP stays off: its routes are excluded above anyway, and leaving the
    // switch off keeps the OAuth server out of the route table entirely.
    MCP_ENABLED: 'false',
  });

  const collected = [];

  const app = await buildApp({
    config,
    logger: false,
    db: stub.db,
    redis: stub.redis,
    instrument: async (instance) => {
      instance.addHook('onRoute', (routeOptions) => {
        collected.push(routeOptions);
      });
      await instance.register(swagger, {
        openapi: {
          openapi: '3.1.0',
          info: {
            title: 'AllisWell REST API',
            version: pkg.version,
            description:
              'Tasks, notes, projects, files and reminders — the same surface ' +
              'the AllisWell apps use, open to your own scripts through a ' +
              'personal API key.',
            license: { name: 'See LICENSE', url: 'https://github.com/mahirozdin/alliswell' },
          },
          servers: [
            { url: 'https://api.alliswell.space', description: 'The hosted service' },
            { url: 'http://localhost:3000', description: 'A local or self-hosted instance' },
          ],
          components: {
            securitySchemes: {
              apiKey: {
                type: 'http',
                scheme: 'bearer',
                description:
                  'A personal API key: `Authorization: Bearer awk_…`. Bound to ' +
                  'one workspace, carries its owner’s full authority there, and ' +
                  'has no scopes in v1 (ADR-0032). Create one in the app under ' +
                  'Settings → API access and management.',
              },
              sessionJwt: {
                type: 'http',
                scheme: 'bearer',
                bearerFormat: 'JWT',
                description:
                  'A 15-minute access token from `POST /api/v1/auth/login`, ' +
                  'refreshed with the rotating refresh token. What the apps use.',
              },
            },
          },
        },
      });
    },
  });

  await app.ready();
  const spec = app.swagger();
  await app.close();

  // Fastify's own schema output is the source; we only annotate it with
  // things the schemas cannot say — which credentials work, and a tag so the
  // rendered page has sections a reader can navigate.
  // Fastify names a path parameter `:workspaceId`; OpenAPI names the same one
  // `{workspaceId}`. Keying the lookup on the raw url silently matches only
  // the routes that have no parameters at all — which is most of `/auth` and
  // almost nothing else, so the spec comes out claiming 96 open endpoints on
  // an API where nearly everything requires a credential. Normalise first.
  const openApiPath = (url) => url.replace(/:([A-Za-z0-9_]+)/g, '{$1}');

  const byUrl = new Map();
  for (const route of collected) {
    // `method` is a string for most routes and an array for the few that
    // register several verbs at once.
    for (const method of [route.method].flat()) {
      byUrl.set(`${String(method).toUpperCase()}:${openApiPath(route.url)}`, route);
    }
  }

  for (const [path, methods] of Object.entries(spec.paths ?? {})) {
    if (EXCLUDED.some((re) => re.test(path))) {
      delete spec.paths[path];
      continue;
    }
    for (const [method, operation] of Object.entries(methods)) {
      const route = byUrl.get(`${method.toUpperCase()}:${path}`);
      operation.tags = [tagFor(path)];
      if (!route) {
        // Every operation in the spec came from a collected route, so a miss
        // means the two sides disagree about how a path is spelled — exactly
        // the bug the normalisation above fixes. Fail loudly rather than
        // publishing an endpoint with no stated auth.
        throw new Error(`No route matched ${method.toUpperCase()} ${path} — cannot state its auth`);
      }
      const { security, note } = securityFor(route, path);
      operation.security = security;
      operation.description = [operation.description, note].filter(Boolean).join('\n\n');
    }
  }

  spec.paths = Object.fromEntries(
    Object.entries(spec.paths ?? {}).sort(([a], [b]) => a.localeCompare(b)),
  );

  return `${JSON.stringify(toOpenApiSchema(spec), null, 2)}\n`;
}

const json = await generate();

if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(OUT, 'utf8');
  } catch {
    console.error('docs/openapi.json is missing. Run: npm run openapi');
    process.exit(1);
  }
  if (current !== json) {
    console.error('docs/openapi.json is out of date — the routes have changed.');
    console.error('Run: npm run openapi   (and commit the result)');
    process.exit(1);
  }
  const count = Object.keys(JSON.parse(json).paths).length;
  console.log(`check:openapi — spec matches the routes (${count} paths).`);
} else {
  writeFileSync(OUT, json);
  const count = Object.keys(JSON.parse(json).paths).length;
  console.log(`Wrote docs/openapi.json (${count} paths).`);
}
