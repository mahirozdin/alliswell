import { describe, it, expect } from 'vitest';
import { slugify, uniqueSlug } from '../../src/lib/slug.js';

describe('slugify (OPH-357)', () => {
  it('UI-AUDIT #81: keeps the Turkish dotless and dotted i', () => {
    expect(slugify('Bakım')).toBe('bakim');
    expect(slugify('Satın Alma')).toBe('satin-alma');
    expect(slugify('İnsan Kaynakları')).toBe('insan-kaynaklari');
    expect(slugify('DIŞ TİCARET')).toBe('dis-ticaret');
  });

  it('still folds the other accented letters and strips punctuation', () => {
    expect(slugify('Şirket Güvenliği & Öğrenim')).toBe('sirket-guvenligi-ogrenim');
    expect(slugify("Mahir's Space")).toBe('mahir-s-space');
    expect(slugify('Café déjà vu')).toBe('cafe-deja-vu');
  });

  it('falls back when nothing slug-safe survives', () => {
    expect(slugify('!!!')).toBe('space');
    expect(slugify('***', 'tag')).toBe('tag');
  });

  it('caps the readable part and adds a random suffix for workspaces', () => {
    expect(slugify('a'.repeat(80))).toHaveLength(48);
    expect(uniqueSlug('Bakım')).toMatch(/^bakim-[0-9a-f]{8}$/);
  });
});
