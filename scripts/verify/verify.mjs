#!/usr/bin/env node
// `npm run verify:task` (K1) and `npm run verify:batch` (K2) for this repo — ADR-0042, LOOP.md.
//
//   npm run verify:task [-- <test files>]   the change in hand: lint/format of the changed
//                                            files, the gates whose input changed, and the
//                                            named tests (or the API unit suite)
//   npm run verify:batch [-- --all]          everything since the last push, once, before it
//   npm run verify:batch -- --list           the plan, without running it
//
// This table IS the check set: CI's jobs, split by where they can run (Flutter here, the
// suites on the sandbox) and by what a change can affect. A gate added to CI is a row here
// too — otherwise K2 goes green on a batch the next CI run turns red.
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CORE_ROOT, existingTargets, runCli } from './engine.mjs';

const under =
  (...prefixes) =>
  (files) =>
    files.some((f) => prefixes.some((p) => f.startsWith(p)));
const any =
  (...tests) =>
  (files) =>
    tests.some((t) => t(files));
const ext = (re) => (files) => files.some((f) => re.test(f));

const APP_DART = (files) => files.filter((f) => /^apps\/app\/(lib|test)\/.*\.dart$/.test(f));
// What the CI formatter checks: the changed Dart files — or, past a few hundred (a batch
// that touched most of the app, or --all), the two directories CI itself formats. A list
// that long would not fit the one command line the sandbox receives.
const FORMAT_SCOPE = (files) =>
  APP_DART(files).length > 200 ? ['apps/app/lib/', 'apps/app/test/'] : APP_DART(files);
const API_JS = (files) => files.filter((f) => /^apps\/api\/.*\.(m?js|json)$/.test(f));
const inApi = (files) => files.map((f) => f.replace(/^apps\/api\//, '')).join(' ');
const inApp = (files) => files.map((f) => f.replace(/^apps\/app\//, '')).join(' ');

// What the API suites read beyond apps/api: the parity fixtures and i18n files shared with
// the app, the landing's enquiry module, the deploy/push scripts some tests import.
const API_INPUTS = under(
  'apps/api/',
  'package.json',
  'package-lock.json',
  'docker-compose.yml',
  'scripts/',
  'apps/app/test/fixtures/',
  'apps/app/assets/i18n/',
  'apps/landing/src/',
);
const APP = under('apps/app/');
const LANDING = under('apps/landing/');

const DB_ENV = {
  // docker-compose.yml's defaults — the stack verify brings up on the sandbox.
  DATABASE_HOST: '127.0.0.1',
  DATABASE_PORT: '3306',
  DATABASE_USER: 'alliswell',
  DATABASE_PASSWORD: 'alliswell_dev',
  DATABASE_NAME: 'alliswell',
  REDIS_URL: 'redis://127.0.0.1:6379',
};
// The shared sandbox is slower than a CI runner: three SSE/socket unit tests and the AI chat
// integration file time out at the default 15/30 s there and pass at 120 s (measured; CI
// passes at the defaults). A hanging test still fails — two minutes later.
const SLOW_HOST = '--testTimeout=120000 --hookTimeout=120000';
const VITEST = '../../node_modules/.bin/vitest';
const FLUTTER_TOUCHED = ['apps/app/analysis_options.yaml', 'apps/app/pubspec.lock'];

// A cheap gate: K2 runs it whatever changed, K1 only when its input changed.
const gate = (name, cmd, taskWhen) => ({
  name,
  where: 'local',
  cwd: '.',
  cmd,
  modes: ['task', 'batch'],
  when: (files, mode) => mode === 'batch' || taskWhen(files),
});

const steps = [
  // ── Policy and docs gates (node or python, seconds) ──
  gate('no-ts', 'npm run -s check:no-ts', ext(/\.tsx?$/)),
  gate('no-ee', 'npm run -s check:no-ee', under('.gitignore', 'ee')),
  gate(
    'docs',
    'npm run -s check:docs',
    any(ext(/\.md$/), under('docs/', 'scripts/docs/', 'scripts/tasks/', 'package.json')),
  ),
  gate(
    'i18n',
    'npm run -s check:i18n',
    under('apps/app/lib/', 'apps/app/assets/i18n/', 'scripts/i18n/'),
  ),
  gate('fab', 'npm run -s check:fab', under('apps/app/lib/', 'scripts/design/')),
  gate('opacity', 'npm run -s check:opacity', under('apps/app/lib/', 'scripts/design/')),
  gate(
    'push-payload',
    'npm run -s check:push-payload',
    under('apps/api/src/lib/push/', 'scripts/push/'),
  ),
  gate(
    'notify-matrix',
    'npm run -s check:notify-matrix',
    under('apps/app/lib/src/notifications/', 'docs/NOTIFICATIONS.md', 'scripts/notifications/'),
  ),
  gate(
    'sync-fields',
    'npm run -s check:sync-fields',
    under('apps/api/src/routes/sync.js', 'apps/app/lib/src/sync/', 'scripts/sync/'),
  ),
  gate(
    'search-reachable',
    'npm run -s check:search-reachable',
    under('apps/app/lib/', 'scripts/search/'),
  ),
  gate('openapi', 'npm run -s check:openapi', under('apps/api/src/', 'scripts/api/')),
  gate('apidocs', 'npm run -s check:apidocs', under('apps/api/src/', 'scripts/api/', 'docs/api/')),
  gate('postman', 'npm run -s check:postman', under('apps/api/src/', 'scripts/api/', 'docs/api/')),
  gate(
    'contrast',
    'python3 scripts/design/contrast.py',
    under('apps/app/lib/src/theme/', 'scripts/design/', 'docs/DESIGN.md'),
  ),
  { ...gate('landing-copy', 'npm run -s check:copy', LANDING), when: LANDING },

  // ── API lint/format: the changed files in K1, the whole package in K2 ──
  {
    name: 'lint',
    where: 'local',
    cwd: 'apps/api',
    modes: ['task'],
    when: (files) => API_JS(files).some((f) => /\.m?js$/.test(f)),
    cmd: (files) => `npx eslint ${inApi(API_JS(files).filter((f) => /\.m?js$/.test(f)))}`,
  },
  {
    name: 'format',
    where: 'local',
    cwd: 'apps/api',
    modes: ['task'],
    when: (files) => API_JS(files).length > 0,
    cmd: (files) => `npx prettier --check ${inApi(API_JS(files))}`,
  },
  {
    name: 'lint',
    where: 'local',
    cwd: '.',
    modes: ['batch'],
    always: true,
    cmd: 'npm run -s lint',
  },
  {
    name: 'format',
    where: 'local',
    cwd: '.',
    modes: ['batch'],
    always: true,
    cmd: 'npm run -s format:check',
  },
  {
    name: 'landing-lint',
    where: 'local',
    cwd: '.',
    modes: ['task', 'batch'],
    when: LANDING,
    cmd: 'npm run -s lint -w @alliswell/landing',
  },

  // ── Flutter (the toolchain is on this machine; queued as heavy work) ──
  {
    name: 'flutter-analyze',
    where: 'local',
    cwd: 'apps/app',
    modes: ['task'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: (files) => APP_DART(files).length > 0,
    cmd: (files) => `flutter analyze ${inApp(APP_DART(files))}`,
  },
  {
    name: 'flutter-analyze',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: APP,
    cmd: 'flutter analyze',
  },
  {
    name: 'flutter-test',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: APP,
    cmd: 'flutter test',
  },
  {
    // CI's web build is the one step that resolves conditional imports; built into a
    // scratch directory so the build/web a local preview serves is left alone.
    name: 'web-build',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: under('apps/app/lib/', 'apps/app/web/', 'apps/app/pubspec.yaml', 'apps/app/packages/'),
    cmd: `flutter build web --release -o ${join(tmpdir(), 'alliswell-verify-web')}`,
  },
  {
    // `flutter analyze` and `flutter test` never compile Swift or Kotlin: a broken native
    // file passes both. Only a platform build does (LESSONS ios-native / android-native).
    name: 'native-android',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: (files) => files.some((f) => /^apps\/app\/(packages\/[^/]+\/)?android\//.test(f)),
    cmd: 'flutter build apk --release && bash ../../scripts/android/assert-permissions.sh',
  },
  {
    name: 'native-ios',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: (files) => files.some((f) => /^apps\/app\/(packages\/[^/]+\/)?ios\//.test(f)),
    cmd: 'flutter build ios --debug --no-codesign',
  },
  {
    name: 'native-macos',
    where: 'local',
    cwd: 'apps/app',
    modes: ['batch'],
    heavy: true,
    restore: FLUTTER_TOUCHED,
    when: (files) => files.some((f) => /^apps\/app\/(packages\/[^/]+\/)?macos\//.test(f)),
    cmd: 'flutter build macos --debug',
  },

  // ── On the sandbox ──
  {
    // Dart format as CI runs it: the local SDK is newer and the two disagree on collection
    // layout (LESSONS ci-release), so the check uses CI's Dart on the sandbox.
    name: 'dart-format',
    where: 'sandbox',
    cwd: '.',
    modes: ['batch'],
    when: (files) => APP_DART(files).length > 0,
    needs: FORMAT_SCOPE,
    cmd: (files) => `bash scripts/verify/dart-format-ci.sh ${FORMAT_SCOPE(files).join(' ')}`,
  },
  {
    name: 'api-unit',
    where: 'sandbox',
    cwd: 'apps/api',
    modes: ['task', 'batch'],
    // K1 runs the whole unit suite only when API code changed and no test was named.
    when: (files, mode, targets) =>
      mode === 'batch' ? API_INPUTS(files) : under('apps/api/src/')(files) && targets.length === 0,
    cmd: `${VITEST} run test/unit ${SLOW_HOST}`,
  },
  {
    // Migrations are a critical path: K1 runs the round trip the moment one changes.
    name: 'migrations',
    where: 'sandbox',
    cwd: 'apps/api',
    modes: ['task', 'batch'],
    db: true,
    when: (files, mode) =>
      mode === 'batch' ? API_INPUTS(files) : under('apps/api/migrations/')(files),
    cmd: 'npm run -s db:migrate && npm run -s db:rollback && npm run -s db:migrate',
  },
  {
    name: 'api-integration',
    where: 'sandbox',
    cwd: 'apps/api',
    modes: ['batch'],
    db: true,
    when: API_INPUTS,
    cmd: `INTEGRATION=1 ${VITEST} run test/integration ${SLOW_HOST}`,
  },
  {
    name: 'landing-build',
    where: 'sandbox',
    cwd: '.',
    modes: ['batch'],
    when: LANDING,
    needs: () => ['screenshots/'],
    cmd: 'npm run -s landing:build && npm run -s check:pages',
  },
];

/** K1 targets: named test files run on their own, where their toolchain lives. */
function targets(paths) {
  const found = existingTargets(CORE_ROOT, paths);
  const dart = found.filter((f) => f.startsWith('apps/app/'));
  const unit = found.filter((f) => f.startsWith('apps/api/test/unit'));
  const integration = found.filter((f) => f.startsWith('apps/api/test/integration'));
  const out = [];
  if (dart.length) {
    out.push({
      name: 'flutter-test:named',
      where: 'local',
      cwd: 'apps/app',
      heavy: true,
      restore: FLUTTER_TOUCHED,
      target: true,
      cmd: `flutter test ${inApp(dart)}`,
    });
  }
  if (unit.length) {
    out.push({
      name: 'api-unit:named',
      where: 'sandbox',
      cwd: 'apps/api',
      target: true,
      cmd: `${VITEST} run ${inApi(unit)} ${SLOW_HOST}`,
    });
  }
  if (integration.length) {
    out.push({
      name: 'api-integration:named',
      where: 'sandbox',
      cwd: 'apps/api',
      db: true,
      target: true,
      cmd: `npm run -s db:migrate && INTEGRATION=1 ${VITEST} run ${inApi(integration)} ${SLOW_HOST}`,
    });
  }
  const unknown = paths.length - dart.length - unit.length - integration.length;
  if (unknown > 0) {
    console.error(
      `verify: ${unknown} target(s) are not a test file under apps/app or apps/api/test — ignored`,
    );
  }
  return out;
}

process.exitCode = await runCli({
  label: 'core',
  repoRoot: CORE_ROOT,
  profile: 'core',
  payload: {
    roots: [{ root: CORE_ROOT, prefix: '' }],
    // The app's sources and the image-heavy trees stay here; the suites read only these
    // parts of apps/app (the parity fixtures and translations shared with the server).
    exclude: [
      'apps/app/',
      'screenshots/',
      'store/',
      'docs/screenshots/',
      'docs/store/',
      '.claude/',
    ],
    include: ['apps/app/test/fixtures/', 'apps/app/assets/i18n/'],
  },
  compose: { file: 'docker-compose.yml', project: 'alliswell' },
  db: { env: DB_ENV },
  steps,
  targets,
  ciOnly: [
    'api-mariadb: migrations and the integration suite on MariaDB 10.11',
    'landing: the docroot, og:image, enterprise-page and legal-page assertions written inline in ci.yml',
    'app: the full `dart format --set-exit-if-changed lib test` (K2 checks the changed files with the same Dart)',
  ],
});
