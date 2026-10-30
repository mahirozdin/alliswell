#!/usr/bin/env node
/**
 * Render every composition into renders/ (gitignored), then
 * `npm run media:promote` at the repo root encodes them for the site.
 *
 *   node scripts/render.mjs                 # everything
 *   node scripts/render.mjs loop-hero film  # names or prefixes
 *
 * The CLI version is pinned so a render is reproducible (ADR-0061).
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HF = 'hyperframes@0.8.221';
const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const vars = (file) => path.join(here, 'film', file);

const JOBS = [
  { out: 'loop-hero', comp: 'loop-hero' },
  { out: 'loop-tour-tasks', comp: 'loop-tour-tasks' },
  { out: 'loop-tour-notes', comp: 'loop-tour-notes' },
  { out: 'loop-tour-alarms', comp: 'loop-tour-alarms' },
  { out: 'loop-tour-files', comp: 'loop-tour-files' },
  { out: 'loop-tour-repeats', comp: 'loop-tour-repeats' },
  { out: 'loop-mcp-en', comp: 'loop-mcp', variables: vars('mcp-en.json') },
  { out: 'loop-mcp-tr', comp: 'loop-mcp', variables: vars('mcp-tr.json') },
  { out: 'loop-selfhost', comp: 'loop-selfhost' },
  { out: 'film-en', comp: 'film', variables: vars('film-en.json') },
  { out: 'film-tr', comp: 'film', variables: vars('film-tr.json') },
];

const wanted = process.argv.slice(2);
const jobs = wanted.length ? JOBS.filter((j) => wanted.some((w) => j.out.startsWith(w))) : JOBS;
if (!existsSync(path.join(here, 'assets/shots'))) execFileSync('node', [path.join(here, 'scripts/shots.mjs')], { stdio: 'inherit' });
if (jobs.some((j) => j.comp === 'film') && !existsSync(path.join(here, 'assets/audio/film-bed.wav'))) {
  execFileSync('python3', [path.join(here, 'scripts/music.py'), '56'], { stdio: 'inherit' });
}
mkdirSync(path.join(here, 'renders'), { recursive: true });
for (const job of jobs) {
  const args = ['--yes', HF, 'render', '-c', `compositions/${job.comp}.html`, '-o', `renders/${job.out}.mp4`, '--quality', 'high', '--fps', '30', '--quiet', '--strict'];
  // `--variables-file` fails in 0.8.221 ("io.readFile is not a function"); the JSON goes inline.
  if (job.variables) args.push('--variables', JSON.stringify(JSON.parse(readFileSync(job.variables, 'utf8'))), '--strict-variables');
  console.log(`render ${job.out}`);
  execFileSync('npx', args, { cwd: here, stdio: ['ignore', 'ignore', 'inherit'] });
}
