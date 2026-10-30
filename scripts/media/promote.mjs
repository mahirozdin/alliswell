#!/usr/bin/env node
/**
 * Promote approved media into the landing site (ADR-0061).
 *
 *   npm run media:promote               # every entry in media/sources.json
 *   npm run media:promote -- hero mcp   # only these keys
 *
 * For each key it encodes what the browser gets, names every file after the
 * sha256 of its bytes (`hero.3f9c0a1b2d.mp4`), writes them under
 * `apps/landing/public/media/`, records them in `apps/landing/src/home/media.json`,
 * and deletes the files the new manifest no longer names. Hashed names are what
 * let `.htaccess` cache media as immutable: a changed file is a new URL.
 *
 * - loop:  HyperFrames render -> silent H.264 MP4 (faststart) + AVIF/JPEG poster.
 *          No render yet: the poster comes from `still` and the entry has no MP4.
 * - film:  render -> H.264 + AAC MP4 + poster + WebVTT captions.
 * - photo: the original (downloaded once into media/.cache) -> AVIF + JPEG widths.
 * - still: a screenshot -> AVIF + JPEG widths, aspect kept.
 *
 * A `readme` block also writes an animated WebP to docs/assets/readme/ (stable
 * name, the README links it), and `readmePoster` a JPEG still.
 *
 * Needs ffmpeg with libx264, libaom-av1 and libwebp. Runs locally; CI only
 * checks the result (`npm run check:media`).
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { BUDGETS } from '../../apps/landing/scripts/media-budgets.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SOURCES = path.join(ROOT, 'media/sources.json');
const PUBLIC = path.join(ROOT, 'apps/landing/public');
const OUT = path.join(PUBLIC, 'media');
const MANIFEST = path.join(ROOT, 'apps/landing/src/home/media.json');
const README_DIR = path.join(ROOT, 'docs/assets/readme');
const CACHE = path.join(ROOT, 'media/.cache');
const TMP = path.join(CACHE, 'tmp');

const LOOP_W = 1600;
const LOOP_H = 1000;
const PAPER = '0x141821';

const run = (args) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...args], { stdio: ['ignore', 'inherit', 'inherit'] });
const probe = (file) =>
  JSON.parse(
    execFileSync('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', file], {
      encoding: 'utf8',
    }),
  );
const sha = (file) => createHash('sha256').update(readFileSync(file)).digest('hex').slice(0, 10);
const size = (file) => statSync(file).size;
const kb = (n) => `${Math.round(n / 1024)} kB`;

/** Move a temp file to its hashed public name; return the URL path. */
function place(tmp, dir, stem, ext) {
  const target = path.join(OUT, dir);
  mkdirSync(target, { recursive: true });
  const name = `${stem}.${sha(tmp)}.${ext}`;
  renameSync(tmp, path.join(target, name));
  return `/media/${dir}/${name}`;
}

const tmpFile = (name) => {
  mkdirSync(TMP, { recursive: true });
  return path.join(TMP, name);
};

/** Encode down a CRF ladder until the file fits `budget` bytes. */
function encodeUnder(budget, label, attempt) {
  for (let crf = 22; crf <= 40; crf += 2) {
    const file = attempt(crf);
    if (size(file) <= budget) {
      console.log(`  ${label}: crf ${crf}, ${kb(size(file))}`);
      return file;
    }
  }
  throw new Error(`${label}: still over ${kb(budget)} at crf 40`);
}

/** One still frame -> AVIF + JPEG at the given widths. */
function posterSet(srcImage, stem, widths, { fit = 'cover', w = LOOP_W, h = LOOP_H } = {}) {
  const frame = tmpFile(`${stem}-frame.png`);
  const vf =
    fit === 'contain'
      ? `scale=-2:${h}:flags=lanczos,pad=${w}:${h}:(ow-iw)/2:0:color=${PAPER}`
      : fit === 'none'
        ? 'null'
        : `scale=${w}:${h}:force_original_aspect_ratio=increase:flags=lanczos,crop=${w}:${h}`;
  run(['-i', srcImage, '-frames:v', '1', '-vf', vf, frame]);
  const out = { avif: [], jpg: [] };
  for (const width of widths) {
    const avif = tmpFile(`${stem}-${width}.avif`);
    run(['-i', frame, '-vf', `scale=${width}:-2:flags=lanczos`, '-c:v', 'libaom-av1', '-still-picture', '1', '-crf', '34', '-cpu-used', '6', '-pix_fmt', 'yuv420p', avif]);
    out.avif.push({ src: place(avif, 'posters', `${stem}-${width}`, 'avif'), w: width });
    const jpg = tmpFile(`${stem}-${width}.jpg`);
    run(['-i', frame, '-vf', `scale=${width}:-2:flags=lanczos`, '-q:v', '5', jpg]);
    out.jpg.push({ src: place(jpg, 'posters', `${stem}-${width}`, 'jpg'), w: width });
  }
  const { streams } = probe(frame);
  rmSync(frame);
  return { poster: out, width: streams[0].width, height: streams[0].height };
}

function readmeWebp(render, { file, width, fps }) {
  mkdirSync(README_DIR, { recursive: true });
  const target = path.join(README_DIR, file);
  for (const q of [70, 60, 50, 40, 30]) {
    run(['-i', render, '-vf', `fps=${fps},scale=${width}:-2:flags=lanczos`, '-an', '-c:v', 'libwebp_anim', '-lossless', '0', '-q:v', String(q), '-compression_level', '6', '-loop', '0', target]);
    if (size(target) <= BUDGETS.readmeAnimated) {
      console.log(`  readme ${file}: q ${q}, ${kb(size(target))}`);
      return;
    }
  }
  throw new Error(`${file}: over the README budget even at q 30`);
}

function readmeJpeg(render, at, { file, width }) {
  mkdirSync(README_DIR, { recursive: true });
  const target = path.join(README_DIR, file);
  run(['-ss', String(at), '-i', render, '-frames:v', '1', '-vf', `scale=${width}:-2:flags=lanczos`, '-q:v', '4', target]);
  console.log(`  readme ${file}: ${kb(size(target))}`);
}

function promoteLoop(key, spec, previous) {
  const render = path.join(ROOT, spec.render);
  if (!existsSync(render)) {
    if (previous?.mp4) {
      console.log(`  ${key}: no render on this machine, keeping the promoted files`);
      return previous;
    }
    console.log(`  ${key}: no render yet, poster from ${spec.still}`);
    return { kind: 'loop', ...posterSet(path.join(ROOT, spec.still), key, [1600, 800], { fit: spec.fit }) };
  }
  const meta = probe(render);
  const duration = Number(meta.format.duration);
  const mp4 = encodeUnder(BUDGETS.loop, `${key} mp4`, (crf) => {
    const f = tmpFile(`${key}.mp4`);
    run(['-i', render, '-an', '-vf', `scale=${LOOP_W}:${LOOP_H}:flags=lanczos`, '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', String(crf), '-movflags', '+faststart', f]);
    return f;
  });
  const frame = tmpFile(`${key}-at.png`);
  run(['-ss', String(spec.posterAt ?? 0), '-i', render, '-frames:v', '1', frame]);
  const posters = posterSet(frame, key, [1600, 800]);
  rmSync(frame);
  if (spec.readme) readmeWebp(render, spec.readme);
  return { kind: 'loop', mp4: place(mp4, 'loops', key, 'mp4'), duration: Math.round(duration * 10) / 10, ...posters };
}

function promoteFilm(key, spec, previous) {
  const render = path.join(ROOT, spec.render);
  if (!existsSync(render)) {
    if (previous?.mp4) return previous;
    console.log(`  ${key}: no render yet, skipped`);
    return null;
  }
  const duration = Number(probe(render).format.duration);
  const mp4 = encodeUnder(BUDGETS.film, `${key} mp4`, (crf) => {
    const f = tmpFile(`${key}.mp4`);
    run(['-i', render, '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', String(crf), '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', f]);
    return f;
  });
  const frame = tmpFile(`${key}-at.png`);
  run(['-ss', String(spec.posterAt ?? 0), '-i', render, '-frames:v', '1', frame]);
  const posters = posterSet(frame, key, [1920, 960], { w: 1920, h: 1080 });
  rmSync(frame);
  const vtt = tmpFile(`${key}.vtt`);
  copyFileSync(path.join(ROOT, spec.captions), vtt);
  if (spec.readmePoster) readmeJpeg(render, spec.posterAt ?? 0, spec.readmePoster);
  return {
    kind: 'film',
    mp4: place(mp4, 'film', key, 'mp4'),
    captions: place(vtt, 'film', key, 'vtt'),
    duration: Math.round(duration * 10) / 10,
    ...posters,
  };
}

async function promotePhoto(key, spec, previous, requested) {
  mkdirSync(CACHE, { recursive: true });
  const original = path.join(CACHE, path.basename(new URL(spec.download).pathname));
  if (!existsSync(original)) {
    // A full run keeps what is promoted; naming the key asks for the original.
    if (previous && !requested) {
      console.log(`  ${key}: original not cached, keeping the promoted files`);
      return previous;
    }
    const res = await fetch(spec.download, {
      headers: { 'User-Agent': 'AllisWell-landing/1.0 (https://alliswell.space; info@bubiapps.com)' },
    });
    if (!res.ok) throw new Error(`${key}: download failed, HTTP ${res.status}`);
    writeFileSync(original, Buffer.from(await res.arrayBuffer()));
  }
  const { x, y, w, h } = spec.crop;
  const cropped = tmpFile(`${key}-crop.png`);
  run(['-i', original, '-vf', `crop=${w}:${h}:${x}:${y}`, cropped]);
  const out = { avif: [], jpg: [] };
  for (const width of [2400, 1600, 960]) {
    const avif = tmpFile(`${key}-${width}.avif`);
    run(['-i', cropped, '-vf', `scale=${width}:-2:flags=lanczos`, '-c:v', 'libaom-av1', '-still-picture', '1', '-crf', '36', '-cpu-used', '6', '-pix_fmt', 'yuv420p', avif]);
    out.avif.push({ src: place(avif, 'photo', `${key}-${width}`, 'avif'), w: width });
  }
  for (const width of [2400, 1280]) {
    const jpg = tmpFile(`${key}-${width}.jpg`);
    run(['-i', cropped, '-vf', `scale=${width}:-2:flags=lanczos`, '-q:v', '7', jpg]);
    out.jpg.push({ src: place(jpg, 'photo', `${key}-${width}`, 'jpg'), w: width });
  }
  rmSync(cropped);
  return { kind: 'photo', width: 2400, height: Math.round((2400 * h) / w), sources: out, credit: spec.credit };
}

function promoteStill(key, spec) {
  const src = path.join(ROOT, spec.src);
  return { kind: 'still', ...posterSet(src, key, spec.widths, { fit: 'none' }) };
}

/** Every file a manifest names, as public URL paths. */
function referenced(manifest) {
  const urls = new Set();
  const walk = (v) => {
    if (typeof v === 'string' && v.startsWith('/media/')) urls.add(v);
    else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  walk(manifest);
  return urls;
}

function prune(manifest) {
  const keep = referenced(manifest);
  const walk = (dir) => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else {
        const url = `/${path.relative(PUBLIC, full).split(path.sep).join('/')}`;
        if (!keep.has(url)) {
          rmSync(full);
          console.log(`  removed ${url}`);
        }
      }
    }
  };
  walk(OUT);
}

const sources = JSON.parse(readFileSync(SOURCES, 'utf8'));
const only = process.argv.slice(2);
const previous = existsSync(MANIFEST) ? JSON.parse(readFileSync(MANIFEST, 'utf8')) : {};
const manifest = { ...previous };
delete manifest.$comment;

for (const [key, spec] of Object.entries(sources)) {
  if (key.startsWith('$')) continue;
  if (only.length && !only.includes(key)) continue;
  console.log(`${key} (${spec.kind})`);
  const before = previous[key];
  const entry =
    spec.kind === 'loop'
      ? promoteLoop(key, spec, before)
      : spec.kind === 'film'
        ? promoteFilm(key, spec, before)
        : spec.kind === 'photo'
          ? await promotePhoto(key, spec, before, only.includes(key))
          : promoteStill(key, spec);
  if (entry) manifest[key] = entry;
  else delete manifest[key];
}
for (const key of Object.keys(manifest)) {
  if (!(key in sources)) delete manifest[key];
}

const ordered = { $comment: 'Generated by `npm run media:promote` from media/sources.json. Do not edit by hand.' };
for (const key of Object.keys(sources)) if (manifest[key]) ordered[key] = manifest[key];
writeFileSync(MANIFEST, `${JSON.stringify(ordered, null, 2)}\n`);
prune(ordered);
rmSync(TMP, { recursive: true, force: true });
console.log(`wrote ${path.relative(ROOT, MANIFEST)}`);
