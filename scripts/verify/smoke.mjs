#!/usr/bin/env node
// `npm run verify:smoke` — the app actually runs (K2, at the end of a phase — ADR-0060).
//
// Every suite builds the API in-process with `app.inject()`; none of them starts the
// server the way a self-hoster does — from `src/server.js`, against a migrated database,
// over a real socket. This does, and drives the core flow through it:
//
//   health/ready → register → create a task over REST and see it in a sync pull →
//   push a project + task through sync and read it back over REST → sign out, and the
//   refresh token is dead
//
// and, when a built web bundle exists (or `--web` builds one), serves it and loads it in
// headless Chromium until Flutter has rendered.
//
// It brings up its own MySQL + Redis (compose project `alliswell-smoke-<pid>`, free
// ports, volumes removed afterwards), so it never touches the stack a contributor runs,
// and it calls nothing paid or external.
//
//   npm run verify:smoke                 the API flow (+ the web bundle if one is built)
//   npm run verify:smoke -- --web        build the web bundle first (needs Flutter)
//   npm run verify:smoke -- --keep       leave the stack up for a look (prints how to stop it)
//   npm run verify:smoke -- --timeout 900  seconds to wait for MySQL/Redis (default 600)
//
// Exit: 0 every step PASS (the web part may be NOT RUN, said so) · 1 a step FAILED ·
//       2 NOT RUN — this machine cannot run it (no Docker), with the reason.
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { createServer } from 'node:net';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const ROOT = resolve(fileURLToPath(import.meta.url), '../../..');
const API_DIR = join(ROOT, 'apps/api');
const WEB_DIR = join(ROOT, 'apps/app/build/web');
const PROJECT = `alliswell-smoke-${process.pid}`;

const { values: args } = parseArgs({
  options: {
    web: { type: 'boolean', default: false },
    keep: { type: 'boolean', default: false },
    // A first MySQL init took 5.5 minutes on a loaded machine (load 18), past the
    // compose healthcheck's 150 s — so the wait is ours, not `compose up --wait`.
    timeout: { type: 'string', default: '600' },
  },
});

const results = [];
const children = [];
const t0 = Date.now();
const log = (line) => console.log(`[smoke ${((Date.now() - t0) / 1000).toFixed(1)}s] ${line}`);
const record = (name, status, detail = '') => {
  results.push({ name, status, detail });
  log(`${status.padEnd(7)} ${name}${detail ? ` — ${detail}` : ''}`);
};

class StepError extends Error {}
const check = (condition, message) => {
  if (!condition) throw new StepError(message);
};

async function step(name, fn) {
  try {
    const detail = await fn();
    record(name, 'PASS', typeof detail === 'string' ? detail : '');
    return true;
  } catch (error) {
    record(
      name,
      'FAIL',
      error instanceof StepError ? error.message : String(error?.stack ?? error),
    );
    return false;
  }
}

function freePort() {
  return new Promise((done, fail) => {
    const server = createServer();
    server.unref();
    server.on('error', fail);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => done(port));
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function run(cmd, cmdArgs, opts = {}) {
  const r = spawnSync(cmd, cmdArgs, { encoding: 'utf8', cwd: ROOT, ...opts });
  return { code: r.status ?? 1, out: `${r.stdout ?? ''}${r.stderr ?? ''}`, error: r.error };
}

const tail = (text, n = 15) => text.trim().split('\n').slice(-n).join('\n');

function compose(composeArgs, env) {
  return run('docker', ['compose', '-p', PROJECT, '-f', 'docker-compose.yml', ...composeArgs], {
    env: { ...process.env, ...env },
    timeout: 300_000,
  });
}

// ── The flow ────────────────────────────────────────────────────────────────

async function http(base, method, path, { body, token } = {}) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    // not JSON — the status says enough
  }
  return { status: res.status, json, text };
}

async function apiFlow(base) {
  const { newId } = await import(join(API_DIR, 'src/lib/ids.js'));
  const session = {};

  await step('API is ready (MySQL + Redis up)', async () => {
    const r = await http(base, 'GET', '/health/ready');
    check(
      r.status === 200 && r.json?.status === 'ok',
      `/health/ready ${r.status} ${r.text.slice(0, 200)}`,
    );
  });

  const registered = await step('register a new account', async () => {
    const r = await http(base, 'POST', '/api/v1/auth/register', {
      body: { email: `smoke-${Date.now()}@example.com`, password: 'smoke-password-1' },
    });
    check(r.status === 201, `register ${r.status} ${r.text.slice(0, 200)}`);
    check(
      r.json?.tokens?.accessToken && r.json?.workspace?.id,
      'no tokens or workspace in the reply',
    );
    session.token = r.json.tokens.accessToken;
    session.refresh = r.json.tokens.refreshToken;
    session.workspace = r.json.workspace.id;
  });
  if (!registered) return;
  const { token, workspace } = session;

  await step('REST create task → sync pull sees it', async () => {
    const created = await http(base, 'POST', `/api/v1/workspaces/${workspace}/tasks`, {
      token,
      body: { title: 'Smoke: REST task' },
    });
    check(
      created.status === 201 || created.status === 200,
      `create ${created.status} ${created.text.slice(0, 200)}`,
    );
    const pull = await http(
      base,
      'GET',
      `/api/v1/sync/pull?workspaceId=${workspace}&sinceRevision=0`,
      {
        token,
      },
    );
    check(pull.status === 200, `pull ${pull.status}`);
    const seen = pull.json.changes.find(
      (c) => c.entityType === 'task' && c.data?.id === created.json.id,
    );
    check(seen?.data?.title === 'Smoke: REST task', 'the REST task is not in the pull');
  });

  await step('sync push project + task → REST reads it', async () => {
    const projectId = newId();
    const taskId = newId();
    const push = await http(base, 'POST', '/api/v1/sync/push', {
      token,
      body: {
        clientId: newId(),
        workspaceId: workspace,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId: newId(),
            entityType: 'project',
            entityId: projectId,
            operation: 'create',
            patch: { name: 'Smoke project', colorRgb: '#112233' },
          },
          {
            clientMutationId: newId(),
            entityType: 'task',
            entityId: taskId,
            operation: 'create',
            patch: { title: 'Smoke: synced task', projectId, priority: 'medium' },
          },
        ],
      },
    });
    check(push.status === 200, `push ${push.status} ${push.text.slice(0, 200)}`);
    const statuses = push.json.results.map((r) => r.status);
    check(
      statuses.every((s) => s === 'applied'),
      `push results ${statuses.join(',')}`,
    );
    const read = await http(base, 'GET', `/api/v1/tasks/${taskId}`, { token });
    check(read.status === 200, `GET task ${read.status}`);
    check(
      read.json.title === 'Smoke: synced task' && read.json.projectId === projectId,
      'REST shows another task',
    );
  });

  await step('sign out → the refresh token is dead', async () => {
    const out = await http(base, 'POST', '/api/v1/auth/logout', {
      body: { refreshToken: session.refresh },
    });
    check(out.status === 204, `logout ${out.status}`);
    const again = await http(base, 'POST', '/api/v1/auth/refresh', {
      body: { refreshToken: session.refresh },
    });
    check(again.status === 401, `refresh after logout answered ${again.status}`);
  });
}

// ── The web bundle ──────────────────────────────────────────────────────────

function findFlutter() {
  if (run('sh', ['-c', 'command -v flutter']).code === 0) return 'flutter';
  const home = join(homedir(), 'flutter/bin/flutter');
  return existsSync(home) ? home : null;
}

function findChrome() {
  for (const name of ['google-chrome', 'chromium', 'chromium-browser']) {
    const r = run('sh', ['-c', `command -v ${name}`]);
    if (r.code === 0) return r.out.trim();
  }
  const cache = join(homedir(), '.cache/ms-playwright');
  if (existsSync(cache)) {
    for (const dir of readdirSync(cache)
      .filter((d) => /^chromium-\d+$/.test(d))
      .sort()
      .reverse()) {
      for (const bin of ['chrome-linux/chrome', 'chrome-linux64/chrome']) {
        if (existsSync(join(cache, dir, bin))) return join(cache, dir, bin);
      }
    }
  }
  for (const path of ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']) {
    if (existsSync(path)) return path;
  }
  return null;
}

async function webFlow(apiBase) {
  const name = 'web bundle boots in headless Chromium';
  if (args.web) {
    const flutter = findFlutter();
    if (!flutter)
      return record(name, 'NOT RUN', '--web asked for a build, but Flutter is not installed here');
    log('building the web bundle (flutter build web --release) …');
    const build = run(
      flutter,
      ['build', 'web', '--release', `--dart-define=ALLISWELL_API_URL=${apiBase}`],
      {
        cwd: join(ROOT, 'apps/app'),
        timeout: 900_000,
      },
    );
    if (build.code !== 0)
      return record(name, 'FAIL', `flutter build web exited ${build.code}\n${tail(build.out)}`);
  }
  if (!existsSync(join(WEB_DIR, 'index.html'))) {
    return record(name, 'NOT RUN', 'no apps/app/build/web — pass --web to build one');
  }
  const chrome = findChrome();
  if (!chrome) return record(name, 'NOT RUN', 'no Chrome/Chromium on this machine');

  const port = await freePort();
  const server = spawn(process.execPath, [join(ROOT, 'scripts/serve-web.mjs'), String(port)], {
    stdio: 'ignore',
  });
  children.push(server);
  await sleep(500);
  await step(name, async () => {
    const index = await fetch(`http://127.0.0.1:${port}/`);
    check(index.status === 200, `index.html ${index.status}`);
    const r = run(
      chrome,
      [
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        '--virtual-time-budget=20000',
        '--dump-dom',
        `http://127.0.0.1:${port}/`,
      ],
      { timeout: 90_000 },
    );
    check(r.code === 0, `chrome exited ${r.code}\n${tail(r.out, 5)}`);
    check(
      /<flutter-view|<flt-glass-pane|<flt-scene-host/.test(r.out),
      'Flutter never rendered (no flutter-view in the DOM)',
    );
    return 'Flutter rendered';
  });
}

// ── Run ─────────────────────────────────────────────────────────────────────

let stackUp = false;
async function teardown() {
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
  if (!stackUp) return;
  if (args.keep) {
    log(`stack kept: docker compose -p ${PROJECT} down -v   (to remove it)`);
    return;
  }
  const down = compose(['down', '-v', '--remove-orphans']);
  log(`teardown: compose down exited ${down.code}`);
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    await teardown();
    process.exit(130);
  });
}

async function main() {
  const docker = run('docker', ['info', '--format', '{{.ServerVersion}}']);
  if (docker.code !== 0) {
    console.log(
      `NOT RUN — Docker is not available here (${tail(docker.out, 1) || docker.error?.message})`,
    );
    return 2;
  }
  const [mysqlPort, redisPort, apiPort] = [await freePort(), await freePort(), await freePort()];
  const env = {
    MYSQL_PORT: String(mysqlPort),
    REDIS_PORT: String(redisPort),
    DATABASE_HOST: '127.0.0.1',
    DATABASE_PORT: String(mysqlPort),
    DATABASE_USER: 'alliswell',
    DATABASE_PASSWORD: 'alliswell_dev',
    DATABASE_NAME: 'alliswell',
    REDIS_URL: `redis://127.0.0.1:${redisPort}`,
    NODE_ENV: 'development',
    HOST: '127.0.0.1',
    PORT: String(apiPort),
    LOG_LEVEL: 'warn',
    CORS_ORIGIN: '*',
  };

  log(`stack: compose project ${PROJECT} (mysql :${mysqlPort}, redis :${redisPort})`);
  stackUp = true;
  const up = compose(['up', '-d', 'mysql', 'redis'], env);
  if (up.code !== 0) {
    record('MySQL + Redis start', 'FAIL', tail(up.out));
    return 1;
  }
  const healthy = await step('MySQL + Redis start', async () => {
    const deadline = Date.now() + Number(args.timeout) * 1000;
    for (;;) {
      const ps = compose(['ps', '--format', '{{.Service}} {{.Health}}'], env);
      const health = Object.fromEntries(
        ps.out
          .trim()
          .split('\n')
          .map((l) => l.trim().split(/\s+/)),
      );
      if (health.mysql === 'healthy' && health.redis === 'healthy') {
        return `healthy in ${((Date.now() - t0) / 1000).toFixed(0)} s`;
      }
      if (Date.now() > deadline) {
        const logs = compose(['logs', '--tail', '10', 'mysql'], env);
        throw new StepError(
          `not healthy after ${args.timeout} s (${ps.out.trim()})\n${tail(logs.out)}`,
        );
      }
      await sleep(3000);
    }
  });
  if (!healthy) return 1;

  const migrate = run('npm', ['run', 'db:migrate', '-w', '@alliswell/api'], {
    env: { ...process.env, ...env },
    timeout: 300_000,
  });
  if (migrate.code !== 0) {
    record('migrations apply to a fresh database', 'FAIL', tail(migrate.out));
    return 1;
  }
  record('migrations apply to a fresh database', 'PASS');

  let apiLog = '';
  const api = spawn(process.execPath, ['src/server.js'], {
    cwd: API_DIR,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  children.push(api);
  api.stdout.on('data', (d) => (apiLog += d));
  api.stderr.on('data', (d) => (apiLog += d));
  const base = `http://127.0.0.1:${apiPort}`;
  const started = await step('API starts from src/server.js', async () => {
    for (let i = 0; i < 120; i += 1) {
      if (api.exitCode !== null)
        throw new StepError(`the server exited ${api.exitCode}\n${tail(apiLog)}`);
      try {
        const r = await fetch(`${base}/health/live`);
        if (r.status === 200) return `listening on :${apiPort}`;
      } catch {
        // not listening yet
      }
      await sleep(500);
    }
    throw new StepError(`no answer on /health/live after 60 s\n${tail(apiLog)}`);
  });
  if (!started) return 1;

  await apiFlow(base);
  await webFlow(base);
  if (api.exitCode !== null) record('API stays up through the flow', 'FAIL', tail(apiLog));
  return results.some((r) => r.status === 'FAIL') ? 1 : 0;
}

let code = 1;
try {
  code = await main();
} catch (error) {
  record('smoke run', 'FAIL', String(error?.stack ?? error));
  code = 1;
} finally {
  await teardown();
}
const counts = ['PASS', 'FAIL', 'NOT RUN'].map(
  (s) => `${results.filter((r) => r.status === s).length} ${s}`,
);
const verdict = code === 0 ? 'PASS' : code === 2 ? 'NOT RUN' : 'FAIL';
const notRun = results.filter((r) => r.status === 'NOT RUN').map((r) => `${r.name}: ${r.detail}`);
console.log(
  `\nverify:smoke ${verdict} — ${counts.join(' · ')} in ${((Date.now() - t0) / 1000).toFixed(0)} s`,
);
for (const line of notRun) console.log(`  NOT RUN ${line}`);
process.exit(code);
