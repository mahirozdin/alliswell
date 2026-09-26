// The machinery behind `npm run verify:task` (K1) and `npm run verify:batch` (K2) — ADR-0042.
//
// Why it exists: the full check set — the gates, lint, both suites, Flutter — takes the
// better part of a quarter hour, and run after every task it turned a 61-task loop into 37
// hours, most of them spent waiting. So a task closes on the narrowest check that proves it
// (K1) and the full set runs once per batch, before the single push (K2). CI still runs
// everything on every push and is read at the start of the next turn (K3); what needs a
// device or a person goes to docs/DEVICE-CHECKS.md (K4).
//
// A repo describes its checks as steps and hands them to `runCli` (scripts/verify/verify.mjs
// for this repo; an extension checked out beside it may bring its own table). A step:
//   { name, cmd, where: 'local'|'sandbox', cwd, modes: ['task'|'batch'], when?(files),
//     db?, heavy?, restore?: [paths], note? }
//   local    runs here, in the checkout (gates, lint, Flutter — the toolchain is local).
//   sandbox  runs on the remote sandbox when one is configured (`sbx` on PATH), against a
//            fresh mirror of the TRACKED tree — so nothing untracked, and no secret, leaves
//            this machine. Without a sandbox (VERIFY_SANDBOX=0, or a contributor's machine)
//            it runs here instead, against `docker compose up -d mysql redis minio`.
// The local leg and the sandbox leg run at the same time: they are the two slow halves
// and neither needs the other.
import { spawn, spawnSync } from 'node:child_process';
import {
  createWriteStream,
  existsSync,
  mkdtempSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

export const CORE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

// ── git ──────────────────────────────────────────────────────────────────────

export function git(args, cwd) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${(r.stderr || '').trim()}`);
  return r.stdout;
}

const nonEmpty = (text) =>
  text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

/** A batch is measured from the last push: the merge-base with the upstream branch. */
export function batchBase(root) {
  for (const ref of ['@{upstream}', 'origin/main']) {
    const r = spawnSync('git', ['merge-base', 'HEAD', ref], { cwd: root, encoding: 'utf8' });
    if (r.status === 0 && r.stdout.trim()) return { ref, sha: r.stdout.trim() };
  }
  return { ref: 'HEAD', sha: 'HEAD' };
}

/** Repo-relative paths changed since `base` (committed or not), plus untracked ones. */
export function changedFiles(root, base = 'HEAD') {
  return [
    ...new Set([
      ...nonEmpty(git(['diff', '--name-only', base], root)),
      ...nonEmpty(git(['ls-files', '--others', '--exclude-standard'], root)),
    ]),
  ].sort();
}

// ── What may leave the machine ───────────────────────────────────────────────
//
// Only what git tracks, or would track (untracked and not ignored) — and even then not a
// file shaped like a secret. `.env` and its backups, signing keys, keystores and
// provisioning profiles have all sat in this checkout; the sandbox's own sync (`sbx push`)
// ignores .gitignore and shipped several of them once. Tracked files cannot be secrets
// (rule 7), so the shape check guards the untracked half, and refuses rather than skips.
const SECRET_SHAPE =
  /(^|\/)(\.env(\.[^/]*)?|[^/]*\.(key|pem|p8|p12|jks|keystore|mobileprovision)|key\.properties)$/i;
const SECRET_EXAMPLE = /(^|\/)\.env(\.[a-z]+)?\.example$/i;

export function secretShaped(files) {
  return files.filter((f) => SECRET_SHAPE.test(f) && !SECRET_EXAMPLE.test(f));
}

/**
 * The files a sandbox run needs, relative to CORE_ROOT.
 * @param {{roots: Array<{root: string, prefix: string}>, exclude: string[], include: string[]}} p
 */
export function payloadFiles({ roots, exclude = [], include = [] }) {
  const out = [];
  for (const { root, prefix } of roots) {
    const listed = git(['ls-files', '-z', '--cached', '--others', '--exclude-standard'], root)
      .split('\0')
      .filter(Boolean);
    for (const file of listed) {
      const path = prefix + file;
      const kept =
        include.some((p) => path.startsWith(p)) || !exclude.some((p) => path.startsWith(p));
      if (!kept) continue;
      const abs = join(root, file);
      // --cached lists a file deleted in the working tree but not yet from the index.
      if (existsSync(abs) && statSync(abs).isFile()) out.push(path);
    }
  }
  return out;
}

// ── The sandbox ──────────────────────────────────────────────────────────────

export function sandboxEnabled() {
  if (process.env.VERIFY_SANDBOX === '0') return false;
  return spawnSync('sh', ['-c', 'command -v sbx'], { encoding: 'utf8' }).status === 0;
}

const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;
const REMOTE_BASE = `/srv/sandbox/tmp/${basename(CORE_ROOT).toLowerCase()}-verify`;

/** `sbx run` keys its workspace on the current directory's name, so always run it from here. */
function sbx(args, { input, onLine } = {}) {
  return new Promise((done) => {
    const child = spawn('sbx', args, {
      cwd: CORE_ROOT,
      env: { ...process.env, SBX_TIMEOUT: process.env.SBX_TIMEOUT || '3600' },
      stdio: [input ? 'pipe' : 'ignore', 'pipe', 'pipe'],
    });
    if (input) {
      // A remote side that exits early (a refused lock, a failed mkdir) closes the pipe;
      // its exit code says why, so an EPIPE here is not the error to report.
      child.stdin.on('error', () => {});
      child.stdin.end(readFileSync(input));
    }
    let text = '';
    const feed = (chunk) => {
      text += chunk;
    };
    if (onLine) {
      createInterface({ input: child.stdout }).on('line', onLine);
      createInterface({ input: child.stderr }).on('line', onLine);
    } else {
      child.stdout.on('data', feed);
      child.stderr.on('data', feed);
    }
    child.on('close', (code) => done({ code: code ?? 1, text }));
  });
}

async function syncToSandbox(config, log) {
  const files = payloadFiles(config.payload);
  const secrets = secretShaped(files);
  if (secrets.length) {
    throw new Error(
      `refusing to send secret-shaped files to the sandbox: ${secrets.join(', ')} — ` +
        'add them to .gitignore (they should never be committable either)',
    );
  }
  const dir = mkdtempSync(join(tmpdir(), 'verify-payload-'));
  const list = join(dir, 'files');
  writeFileSync(list, files.join('\0'));
  const tgz = join(dir, 'payload.tgz');
  const tar = spawnSync(
    'tar',
    ['--no-xattrs', '-czf', tgz, '-C', CORE_ROOT, '--null', '-T', list],
    // Without these, macOS tar adds an AppleDouble `._name` twin for every file carrying an
    // extended attribute, and knex tries to import `._<migration>.js` as code.
    { env: { ...process.env, COPYFILE_DISABLE: '1' }, encoding: 'utf8' },
  );
  if (tar.status !== 0) throw new Error(`tar: ${tar.stderr}`);
  const size = statSync(tgz).size;
  log(`sandbox: sending ${files.length} tracked files (${(size / 1048576).toFixed(1)} MB)`);
  const incoming = `${REMOTE_BASE}/in-${config.profile}`;
  const r = await sbx(
    [
      'run',
      [
        'set -e',
        `mkdir -p ${shq(REMOTE_BASE)}`,
        `exec 9>${shq(`${REMOTE_BASE}/.lock`)}`,
        'flock -w 900 9',
        `rm -rf ${shq(incoming)}`,
        `mkdir -p ${shq(incoming)}`,
        `tar -xzf - -C ${shq(incoming)}`,
        `bash ${shq(`${incoming}/scripts/verify/sandbox-lib.sh`)} prep ${shq(config.profile)} ${shq(REMOTE_BASE)}`,
      ].join('; '),
    ],
    { input: tgz },
  );
  if (r.code !== 0) throw new Error(`sandbox sync failed (exit ${r.code}):\n${r.text.trim()}`);
  for (const l of nonEmpty(r.text)) log(`sandbox: ${l}`);
  return `${REMOTE_BASE}/${config.profile}`;
}

// ── Running steps ────────────────────────────────────────────────────────────

// Heavy local work (Flutter) goes through the machine's heavy-job queue when there is one,
// so two sessions never run two Flutter suites at once. VERIFY_HEAVY_WRAPPER overrides.
function heavyWrapper() {
  if (process.env.VERIFY_HEAVY_WRAPPER !== undefined)
    return process.env.VERIFY_HEAVY_WRAPPER || null;
  const queue = join(homedir(), '.claude/bin/heavy-queue');
  return existsSync(queue) ? queue : null;
}

function runLocal(step, logFile) {
  const cwd = join(CORE_ROOT, step.cwd || '.');
  const snapshots = (step.restore || [])
    .map((p) => join(CORE_ROOT, p))
    .filter((p) => existsSync(p))
    .map((p) => [p, readFileSync(p)]);
  const wrapper = step.heavy ? heavyWrapper() : null;
  const argv = wrapper ? [wrapper, '--', 'bash', '-c', step.cmd] : ['bash', '-c', step.cmd];
  return new Promise((done) => {
    const out = createWriteStream(logFile);
    const t0 = Date.now();
    const child = spawn(argv[0], argv.slice(1), {
      cwd,
      env: { ...process.env, HEAVY_LABEL: `verify ${step.name}`, ...(step.env || {}) },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.pipe(out, { end: false });
    child.stderr.pipe(out, { end: false });
    child.on('close', (code) => {
      out.end();
      // `flutter pub get` (and so `flutter test`) rewrites two tracked files on every run
      // with this toolchain; put back exactly what was there, committed or not.
      for (const [p, bytes] of snapshots) {
        if (!readFileSync(p).equals(bytes)) writeFileSync(p, bytes);
      }
      done({ code: code ?? 1, secs: (Date.now() - t0) / 1000 });
    });
  });
}

function remoteScript(steps, tree, config) {
  const env = Object.entries(config.db.env)
    .map(([k, v]) => `${k}=${shq(v)}`)
    .join(' ');
  const body = [
    '#!/bin/bash',
    'set -u',
    'exec 2>&1',
    `T=${shq(tree)}`,
    `export ${env}`,
    'DB_OK=0',
    // Every step's stdin is /dev/null: a step that reads stdin would otherwise swallow
    // nothing here, but the habit keeps a later `bash -s` variant of this script honest.
    'step() {',
    '  local name=$1 dir=$2 cmd=$3 needs=$4',
    '  if [ "$needs" = db ] && [ "$DB_OK" != 1 ]; then echo "@@verify skip $name db"; return; fi',
    '  echo "@@verify begin $name"',
    '  local t0=$SECONDS',
    '  ( cd "$T/$dir" && eval "$cmd" ) < /dev/null',
    '  local code=$?',
    '  echo "@@verify end $name $code $((SECONDS - t0))"',
    '  return $code',
    '}',
  ];
  if (steps.some((s) => s.db)) {
    body.push(
      `step db-fresh . ${shq(`bash scripts/verify/sandbox-lib.sh db ${config.compose.project} ${config.db.env.DATABASE_NAME}`)} - && DB_OK=1`,
    );
  }
  for (const s of steps)
    body.push(`step ${shq(s.name)} ${shq(s.cwd || '.')} ${shq(s.cmd)} ${s.db ? 'db' : '-'}`);
  return `${body.join('\n')}\n`;
}

async function runSandboxLeg(steps, config, ctx) {
  const results = new Map();
  const tree = await syncToSandbox(config, ctx.log);
  if (steps.some((s) => s.db)) {
    ctx.log(`sandbox: sbx up (${config.compose.project})`);
    const up = await sbx(['up', `${tree}/${config.compose.file}`]);
    // A clash on a port another project holds (Redis 6379, measured) makes `up` exit
    // non-zero while MySQL and MinIO are fine; the health wait in db-fresh is the judge.
    if (up.code !== 0) ctx.log(`sandbox: sbx up exited ${up.code} — the database wait decides`);
    ctx.upped = true;
  }
  const script = Buffer.from(remoteScript(steps, tree, config)).toString('base64');
  let current = null;
  let stream = null;
  const r = await sbx(
    [
      'run',
      [
        `exec 9>${shq(`${REMOTE_BASE}/.lock`)}`,
        'flock -w 900 9 || { echo "@@verify busy"; exit 75; }',
        `echo ${script} | base64 -d > ${shq(`${REMOTE_BASE}/run-${config.profile}.sh`)}`,
        `bash ${shq(`${REMOTE_BASE}/run-${config.profile}.sh`)}`,
      ].join('; '),
    ],
    {
      onLine: (line) => {
        const m = /^@@verify (begin|end|skip|busy)\s*(\S*)\s*(\S*)\s*(\S*)/.exec(line);
        if (!m) {
          if (stream) stream.write(`${line}\n`);
          return;
        }
        const [, kind, name, code, secs] = m;
        if (kind === 'busy') {
          ctx.log('sandbox: another verify holds the lock for 15 minutes — giving up');
        } else if (kind === 'begin') {
          current = name;
          stream = createWriteStream(ctx.logPath(name));
          ctx.started(name, 'sandbox');
        } else if (kind === 'end') {
          stream?.end();
          stream = null;
          const result = { code: Number(code), secs: Number(secs), where: 'sandbox' };
          results.set(name, result);
          ctx.finished(name, result);
          current = null;
        } else if (kind === 'skip') {
          const result = {
            code: 99,
            secs: 0,
            where: 'sandbox',
            notRun: `needs the database (${code})`,
          };
          results.set(name, result);
          ctx.finished(name, result);
        }
      },
    },
  );
  if (stream) stream.end();
  if (current)
    results.set(current, { code: 1, secs: 0, where: 'sandbox', notRun: 'connection ended' });
  for (const s of steps) {
    if (!results.has(s.name)) {
      results.set(s.name, {
        code: 1,
        secs: 0,
        where: 'sandbox',
        notRun: `sandbox run exited ${r.code}`,
      });
    }
  }
  return results;
}

// No sandbox: the same steps, here, against the compose stack a contributor already runs
// (`docker compose up -d mysql redis minio`, CONTRIBUTING.md) — with the same fresh database.
function localFallback(steps, config) {
  const env = (s) => ({ ...config.db.env, ...(s.env || {}) });
  const out = steps.map((s) => ({ ...s, env: env(s) }));
  if (steps.some((s) => s.db)) {
    const { DATABASE_USER: user, DATABASE_PASSWORD: pass, DATABASE_NAME: name } = config.db.env;
    out.unshift({
      name: 'db-fresh',
      where: 'local',
      cwd: '.',
      env: env({}),
      cmd:
        `docker compose exec -T mysql mysql -u${user} -p${pass} -e ` +
        `"drop database if exists ${name}; create database ${name} character set utf8mb4 collate utf8mb4_0900_ai_ci"`,
    });
  }
  return out;
}

async function runLocalLeg(steps, ctx, { asSandbox = false } = {}) {
  const results = new Map();
  for (const step of steps) {
    ctx.started(step.name, asSandbox ? 'local (no sandbox)' : 'local');
    const result = { ...(await runLocal(step, ctx.logPath(step.name))), where: 'local' };
    results.set(step.name, result);
    ctx.finished(step.name, result);
  }
  return results;
}

// ── The CLI every repo's verify.mjs hands its table to ───────────────────────

const fmtSecs = (s) =>
  s >= 60
    ? `${Math.floor(s / 60)}m ${String(Math.round(s % 60)).padStart(2, '0')}s`
    : `${s.toFixed(1)}s`;

export async function runCli(config) {
  let parsed;
  try {
    parsed = parseArgs({
      allowPositionals: true,
      options: {
        all: { type: 'boolean', default: false },
        since: { type: 'string' },
        only: { type: 'string' },
        skip: { type: 'string' },
        list: { type: 'boolean', default: false },
        'keep-stack': { type: 'boolean', default: false },
      },
    });
  } catch (error) {
    console.error(`verify: ${error.message}`);
    return 2;
  }
  const [mode, ...targets] = parsed.positionals;
  const opts = parsed.values;
  if (mode !== 'task' && mode !== 'batch') {
    console.error(
      'usage: verify task [test files…]   K1 — the narrowest check for the change in hand\n' +
        '       verify batch [--all] [--since <ref>] [--only a,b] [--skip a,b] [--list] [--keep-stack]\n' +
        '                                    K2 — the full set for everything since the last push',
    );
    return 2;
  }

  const base =
    mode === 'task'
      ? { ref: 'HEAD', sha: 'HEAD' }
      : opts.since
        ? { ref: opts.since, sha: opts.since }
        : batchBase(config.repoRoot);
  // --all is "as if every file had changed": each step runs, and a step that works on the
  // changed files (lint, the CI formatter) works on all of them — CI's own scope.
  const files = opts.all
    ? nonEmpty(git(['ls-files'], config.repoRoot))
    : changedFiles(config.repoRoot, base.sha);
  const split = (v) =>
    v
      ? v
          .split(',')
          .map((x) => x.trim())
          .filter(Boolean)
      : [];
  const only = split(opts.only);
  const skip = split(opts.skip);

  const plan = [];
  const skipped = [];
  const candidates = [...config.steps.filter((s) => s.modes.includes(mode))];
  if (mode === 'task') candidates.push(...config.targets(targets));
  for (const step of candidates) {
    // The sandbox leg reports steps as `@@verify end <name> <code> <secs>` lines.
    if (!/^[\w:.-]+$/.test(step.name))
      throw new Error(`verify: step name "${step.name}" must be one word`);
    if (only.length && !only.includes(step.name)) continue;
    if (skip.includes(step.name)) {
      skipped.push([step.name, '--skip']);
      continue;
    }
    const relevant =
      step.always ||
      opts.all ||
      step.target ||
      (step.when ? step.when(files, mode, targets) : true);
    if (!relevant) {
      skipped.push([step.name, 'nothing it checks changed']);
      continue;
    }
    // A command may depend on the change (lint the changed files); settle it once, here.
    plan.push({ ...step, cmd: typeof step.cmd === 'function' ? step.cmd(files) : step.cmd });
  }
  // Steps that need files the default payload leaves out (a changed Dart file for the
  // formatter, the screenshots for the landing build) add them for this run only.
  const payload = {
    ...config.payload,
    include: [
      ...(config.payload.include || []),
      ...plan.flatMap((s) => (s.needs ? s.needs(files) : [])),
    ],
  };

  const useSandbox = sandboxEnabled();
  const localSteps = plan.filter((s) => s.where === 'local');
  const remoteSteps = plan.filter((s) => s.where === 'sandbox');
  const layer = mode === 'task' ? 'K1 verify:task' : 'K2 verify:batch';
  console.log(
    `${layer} — ${config.label}: ${plan.length} step(s) (${localSteps.length} local, ${remoteSteps.length} ` +
      `${useSandbox ? 'sandbox' : 'local-for-sandbox'}) · ` +
      (opts.all
        ? `--all (${files.length} tracked files)`
        : `${files.length} changed file(s) since ${base.ref}`),
  );
  if (opts.list || plan.length === 0) {
    for (const s of plan) console.log(`  RUN   ${s.name.padEnd(24)} ${s.where.padEnd(8)} ${s.cmd}`);
    for (const [n, why] of skipped) console.log(`  SKIP  ${n.padEnd(24)} ${why}`);
    if (plan.length === 0) console.log('Nothing to check for this change.');
    return 0;
  }

  const logDir = mkdtempSync(join(tmpdir(), `verify-${mode}-`));
  const t0 = Date.now();
  const ctx = {
    upped: false,
    log: (line) => console.log(`  · ${line}`),
    logPath: (name) => join(logDir, `${name}.log`),
    started: (name, where) => console.log(`  ▶ ${name} (${where})`),
    finished: (name, r) =>
      console.log(
        `  ${r.notRun ? 'NOT RUN' : r.code === 0 ? 'PASS' : 'FAIL'}  ${name} ${fmtSecs(r.secs)}` +
          (r.notRun ? ` — ${r.notRun}` : ''),
      ),
  };

  const legs = [runLocalLeg(localSteps, ctx)];
  if (remoteSteps.length) {
    legs.push(
      useSandbox
        ? runSandboxLeg(remoteSteps, { ...config, payload }, ctx).catch((error) => {
            ctx.log(error.message);
            return new Map(
              remoteSteps.map((s) => [
                s.name,
                { code: 1, secs: 0, where: 'sandbox', notRun: 'sandbox unavailable' },
              ]),
            );
          })
        : runLocalLeg(localFallback(remoteSteps, config), ctx, { asSandbox: true }),
    );
  }
  const results = new Map();
  for (const leg of await Promise.all(legs)) for (const [k, v] of leg) results.set(k, v);

  // K2 owns the stack's lifetime: bring it down so nothing keeps running on a shared host.
  // K1 leaves it up for the next task's check; the sandbox's TTL reaper is the backstop.
  if (ctx.upped && mode === 'batch' && !opts['keep-stack']) {
    const down = await sbx(['down']);
    ctx.log(`sandbox: sbx down (exit ${down.code})`);
  }

  const failed = [...results].filter(([, r]) => r.code !== 0);
  const total = (Date.now() - t0) / 1000;
  console.log(`\n${'─'.repeat(72)}`);
  for (const [name, r] of results) {
    const state = r.notRun ? 'NOT RUN' : r.code === 0 ? 'PASS' : 'FAIL';
    console.log(`  ${state.padEnd(8)} ${name.padEnd(24)} ${r.where.padEnd(8)} ${fmtSecs(r.secs)}`);
  }
  for (const [n, why] of skipped) console.log(`  ${'SKIP'.padEnd(8)} ${n.padEnd(24)} ${why}`);
  if (mode === 'batch' && config.ciOnly?.length) {
    console.log('  CI only (K3 — read at the start of the next turn):');
    for (const note of config.ciOnly) console.log(`    · ${note}`);
  }
  for (const [name] of failed) {
    const log = ctx.logPath(name);
    if (!existsSync(log)) continue;
    const tail = readFileSync(log, 'utf8').trimEnd().split('\n').slice(-40);
    console.log(`\n── ${name} (last ${tail.length} lines; full log ${log})`);
    console.log(tail.join('\n'));
  }
  const verdict = failed.length ? 'FAIL' : 'PASS';
  const partial = only.length > 0 || skip.length > 0;
  console.log(
    `\n${layer} ${verdict} in ${fmtSecs(total)}` +
      (failed.length
        ? ` — ${failed.length} step(s) red; fix, commit, re-run. No push while red.`
        : mode !== 'batch'
          ? ''
          : partial
            ? ' — a partial run (--only/--skip): not a push verdict.'
            : ' — the batch may be pushed.'),
  );
  console.log(`logs: ${logDir}`);
  return failed.length ? 1 : 0;
}

/** K1 targets as paths relative to `root`, keeping only those that exist. */
export function existingTargets(root, targets) {
  return targets.map((t) => relative(root, resolve(t))).filter((t) => existsSync(join(root, t)));
}
