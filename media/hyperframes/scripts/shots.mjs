#!/usr/bin/env node
/**
 * Copy the screenshots the compositions use into assets/shots/ (gitignored).
 * The repo keeps one copy of every capture, in /screenshots and
 * /docs/screenshots; HyperFrames serves only this project's folder.
 */
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.resolve(here, '../..');
const SHOTS = [
  'screenshots/web/home-dark.png',
  'screenshots/web/home-light.png',
  'screenshots/web/board.png',
  'screenshots/web/projects.png',
  'screenshots/web/project-readme.png',
  'screenshots/web/note-editor.png',
  'screenshots/web/notes.png',
  'screenshots/web/files.png',
  'screenshots/web/search.png',
  'screenshots/android/09-alarm-ring.png',
  'screenshots/android/10-home-dark.png',
  'screenshots/ios/05-files.png',
  'screenshots/ios/07-task-detail-repeat.png',
  'screenshots/ios/10-home-dark.png',
  'screenshots/ios/12-widget.png',
  'docs/screenshots/markdown-reading-dark.png',
];
const out = path.join(here, 'assets/shots');
mkdirSync(out, { recursive: true });
for (const rel of SHOTS) {
  const name = rel.split('/').slice(-2).join('-');
  copyFileSync(path.join(repo, rel), path.join(out, name));
}
// The hero photograph, for the film's first and last scenes. `npm run
// media:promote` downloads the original into media/.cache once.
const fog = path.join(repo, 'media/.cache/Vallee-brouillard.jpg');
if (existsSync(fog)) {
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', fog, '-vf', 'scale=2400:-2', '-q:v', '3', path.join(out, 'fog-2400.jpg')]);
} else {
  // No original cached (a fresh clone): use the committed, promoted 2400px JPEG.
  const manifest = JSON.parse(readFileSync(path.join(repo, 'apps/landing/src/home/media.json'), 'utf8'));
  const jpg = manifest['photo-fog'].sources.jpg.find((j) => j.w === 2400);
  copyFileSync(path.join(repo, 'apps/landing/public', jpg.src), path.join(out, 'fog-2400.jpg'));
}
console.log(`copied ${SHOTS.length} screenshots to assets/shots/`);
