import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';
import { describe, expect, test } from 'vitest';

import {
  DEMO_FILE_NAMES,
  LEGACY_PLACEHOLDER_BYTES,
  canvas,
  crc32,
  demoFile,
  isLegacyPlaceholder,
  pdf,
} from '../../../../scripts/seed-demo-files.mjs';

/// OPH-414 — the demo workspace's files are real files. Before, every one was
/// `n` kB of spaces, so no thumbnail or PDF preview could ever render in a
/// screenshot. These tests read the bytes the way a decoder would.

const SEED = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '../../../../scripts/seed-demo.mjs'),
  'utf8',
);

/** PNG chunks, each with its CRC checked. */
function pngChunks(buf) {
  expect([...buf.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const chunks = [];
  let at = 8;
  while (at < buf.length) {
    const len = buf.readUInt32BE(at);
    const type = buf.subarray(at + 4, at + 8).toString('latin1');
    const data = buf.subarray(at + 8, at + 8 + len);
    const crc = buf.readUInt32BE(at + 8 + len);
    expect(crc32(buf.subarray(at + 4, at + 8 + len))).toBe(crc);
    chunks.push({ type, data });
    at += 12 + len;
  }
  return chunks;
}

describe('crc32', () => {
  test('matches the PNG specification check value', () => {
    expect(crc32(Buffer.from('123456789'))).toBe(0xcbf43926);
    expect(crc32(Buffer.from('IEND', 'latin1'))).toBe(0xae426082);
  });
});

describe('PNG builder', () => {
  test('writes a decodable truecolour image of the asked size', () => {
    const c = canvas(3, 2, [10, 20, 30]);
    c.rect(1, 1, 1, 1, [255, 0, 0]);
    const chunks = pngChunks(c.toPng());
    expect(chunks.map((x) => x.type)).toEqual(['IHDR', 'IDAT', 'IEND']);
    const ihdr = chunks[0].data;
    expect([ihdr.readUInt32BE(0), ihdr.readUInt32BE(4), ihdr[8], ihdr[9]]).toEqual([3, 2, 8, 2]);
    const raw = inflateSync(chunks[1].data);
    expect(raw.length).toBe((3 * 3 + 1) * 2);
    // Row 1, pixel 1 (after the filter byte) is the red square.
    expect([...raw.subarray(10 + 1 + 3, 10 + 1 + 6)]).toEqual([255, 0, 0]);
    expect([...raw.subarray(1, 4)]).toEqual([10, 20, 30]);
  });
});

describe('PDF builder', () => {
  test('every xref offset points at its object and startxref at the table', () => {
    const doc = pdf(
      [[{ text: 'Hello (world) \\ back', x: 56, y: 700 }], [{ rect: [0, 0, 10, 10], gray: 0.5 }]],
      { title: 'T' },
    ).toString('latin1');
    expect(doc.startsWith('%PDF-1.4\n')).toBe(true);
    expect(doc.trimEnd().endsWith('%%EOF')).toBe(true);
    const startxref = Number(/startxref\n(\d+)\n/.exec(doc)[1]);
    expect(doc.slice(startxref, startxref + 4)).toBe('xref');
    const rows = doc.slice(startxref).split('\n').slice(3);
    const count = Number(/xref\n0 (\d+)\n/.exec(doc)[1]);
    for (let n = 1; n < count; n += 1) {
      const offset = Number(rows[n - 1].slice(0, 10));
      expect(doc.slice(offset, offset + `${n} 0 obj`.length)).toBe(`${n} 0 obj`);
    }
    expect(doc).toContain('/Count 2');
    // The three PDF string specials are escaped.
    expect(doc).toContain('(Hello \\(world\\) \\\\ back)');
  });
});

describe('demo files', () => {
  test('the seed uploads exactly the files the builders know', () => {
    const names = [...SEED.matchAll(/\{ name: '([^']+)', folder: '[a-z]+' \}/g)].map((m) => m[1]);
    expect(names.sort()).toEqual([...DEMO_FILE_NAMES].sort());
  });

  test.each(DEMO_FILE_NAMES)('%s is a real file of its type, built the same way twice', (name) => {
    const { mime, bytes } = demoFile(name);
    expect(bytes.equals(demoFile(name).bytes)).toBe(true);
    // Small enough for a demo, never a placeholder's size.
    expect(bytes.length).toBeLessThan(200 * 1024);
    expect(isLegacyPlaceholder({ name, sizeBytes: bytes.length })).toBe(false);
    if (name.endsWith('.png')) {
      expect(mime).toBe('image/png');
      const ihdr = pngChunks(bytes)[0].data;
      expect(ihdr.readUInt32BE(0)).toBeGreaterThanOrEqual(640);
    } else if (name.endsWith('.pdf')) {
      expect(mime).toBe('application/pdf');
      expect(bytes.subarray(0, 8).toString('latin1')).toBe('%PDF-1.4');
      expect(bytes.toString('latin1')).toMatch(/\/Type \/Page /);
    } else if (name.endsWith('.svg')) {
      expect(mime).toBe('image/svg+xml');
      expect(bytes.toString('utf8')).toMatch(
        /^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg" viewBox=/,
      );
    } else {
      throw new Error(`no assertion for ${name}`);
    }
  });

  test('an unknown name is refused rather than uploaded empty', () => {
    expect(() => demoFile('nope.txt')).toThrow(/no demo file/);
  });
});

describe('isLegacyPlaceholder', () => {
  test('recognises the old space-filled stand-ins by name and exact size', () => {
    expect(isLegacyPlaceholder({ name: 'floor-plan.png', sizeBytes: 840 * 1024 })).toBe(true);
    expect(isLegacyPlaceholder({ name: 'counter-samples.jpg', sizeBytes: 1650 * 1024 })).toBe(true);
    // Same name, another size: a user's real file, kept.
    expect(isLegacyPlaceholder({ name: 'floor-plan.png', sizeBytes: 840 * 1024 + 1 })).toBe(false);
    expect(isLegacyPlaceholder({ name: 'holiday.png', sizeBytes: 840 * 1024 })).toBe(false);
    expect(isLegacyPlaceholder(null)).toBe(false);
    expect(Object.keys(LEGACY_PLACEHOLDER_BYTES)).toHaveLength(7);
  });
});
