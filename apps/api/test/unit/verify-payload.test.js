import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { describe, expect, test } from 'vitest';

import { payloadFiles, secretShaped } from '../../../../scripts/verify/engine.mjs';

/// ADR-0042 — `verify:batch` runs the suites on a remote sandbox against a mirror
/// of the tree. What may leave the machine is decided here: only what git tracks
/// or would track, minus the app's own sources, and never a file shaped like a
/// secret. The sandbox's own sync ignores .gitignore and once shipped `.env`,
/// `.env.production` and a signing key; these cases are that list.

describe('secretShaped', () => {
  test('flags the shapes a secret has taken in this checkout', () => {
    const secrets = [
      '.env',
      '.env.production',
      '.env.bak.1787050030',
      'ee/tools/license/bubiapps-signing.key',
      'apps/app/android/key.properties',
      'apps/app/android/app/key0.jks',
      'certs/server.pem',
      'AuthKey_ABC123.p8',
      'dist/cert.p12',
      'release.keystore',
      'ios/profile.mobileprovision',
    ];
    expect(secretShaped(secrets)).toEqual(secrets);
  });

  test('lets the examples and ordinary files through', () => {
    expect(
      secretShaped([
        '.env.example',
        '.env.selfhost.example',
        'docs/keys.md',
        'apps/api/src/lib/api-keys.js',
        'scripts/push/allowed-payload-keys.txt',
        'tools/license/bubiapps-signing.pub',
      ]),
    ).toEqual([]);
  });
});

describe('payloadFiles', () => {
  function repo() {
    const root = mkdtempSync(join(tmpdir(), 'verify-payload-'));
    const put = (path, text = 'x') => {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), text);
    };
    const git = (...args) =>
      execFileSync('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...args], { cwd: root });
    git('init', '-q');
    put('.gitignore', '.env\n');
    put('a.txt');
    put('apps/app/lib/x.dart');
    put('apps/app/test/fixtures/f.json');
    put('docs/screenshots/s.png');
    put('gone.txt');
    git('add', '.');
    git('commit', '-qm', 'init');
    put('new.txt'); // untracked, not ignored: it would be committable, so it goes
    put('.env', 'SECRET=1'); // ignored: it stays
    rmSync(join(root, 'gone.txt')); // still in the index, gone from the tree: skipped
    return root;
  }

  test('tracked and committable files, minus the excluded trees, plus the re-included ones', () => {
    const root = repo();
    const files = payloadFiles({
      roots: [{ root, prefix: '' }],
      exclude: ['apps/app/', 'docs/screenshots/'],
      include: ['apps/app/test/fixtures/'],
    });
    expect(files.sort()).toEqual([
      '.gitignore',
      'a.txt',
      'apps/app/test/fixtures/f.json',
      'new.txt',
    ]);
  });

  test('a nested repo is listed under its prefix', () => {
    const root = repo();
    const files = payloadFiles({ roots: [{ root, prefix: 'ee/' }], exclude: ['ee/apps/'] });
    expect(files.sort()).toEqual([
      'ee/.gitignore',
      'ee/a.txt',
      'ee/docs/screenshots/s.png',
      'ee/new.txt',
    ]);
  });
});
