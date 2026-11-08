import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
  addressOf,
  flatten,
  licenceProblems,
  loadSurfaces,
  surfaceOf,
  toneProblems,
} from '../../../../scripts/i18n/tone.mjs';

/// OPH-407 (U-10, DESIGN §45) — check:i18n's tone and licence rules.
///
/// The personal app speaks "sen", the extension's screens "siz", and no
/// string mixes them; neither catalogue calls the app open source.

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const catalogue = (lang) =>
  flatten(JSON.parse(readFileSync(resolve(ROOT, `apps/app/assets/i18n/${lang}.json`), 'utf8')));
const SURFACES = ['ee.*', 'error.EXT_ONLY'];

describe('addressOf — the words that say "sen" or "siz"', () => {
  test.each([
    ['İstediğiniz yere sürükleyin', ['istediğiniz', 'sürükleyin']],
    ['Bu takımın üyesi değilsiniz', ['değilsiniz']],
    ['Başkalarının yaptıkları size hangi kanaldan ulaşsın', ['size']],
    ['Bir birim seçin', ['seçin']],
    ['Çevrimdışısınız — bağlantı açılamıyor', ['çevrimdışısınız']],
  ])('siz: %s', (text, words) => {
    expect(addressOf(text)).toEqual({ sen: [], siz: words });
  });

  test.each([
    ['Ne istiyorsun? Bir servis seç', ['istiyorsun']],
    ['O ana kadar geri alabilirsin.', ['alabilirsin']],
    ['biriminde değilsin', ['değilsin']],
    ['adres verirsen ona bir bağlantı gider', ['verirsen']],
    ['senin değerin kalır', ['senin']],
  ])('sen: %s', (text, words) => {
    expect(addressOf(text)).toEqual({ sen: words, siz: [] });
  });

  test('look-alikes are not markers', () => {
    for (const text of [
      'Henüz görev yok',
      'Yalnız işaretler',
      'Markdown önizleme',
      'Ayın günü',
      'Bu görev için uyarı gelmez',
      'Sil',
      'Kaydet',
      'Bir talep görsün',
    ]) {
      expect(addressOf(text), text).toEqual({ sen: [], siz: [] });
    }
  });

  test('quotes, placeholders and code are not read', () => {
    expect(addressOf('Düğmede “Seçin” yazar')).toEqual({ sen: [], siz: [] });
    expect(addressOf('{seçin} ile')).toEqual({ sen: [], siz: [] });
    expect(addressOf('Sınırı yükselt (client_max_body_size 10m)')).toEqual({ sen: [], siz: [] });
  });
});

describe('surfaceOf — which address a key owes', () => {
  test('the extension and its listed keys say "siz", everything else "sen"', () => {
    expect(surfaceOf('ee.tickets.new.pickService', SURFACES)).toBe('siz');
    expect(surfaceOf('error.EXT_ONLY', SURFACES)).toBe('siz');
    expect(surfaceOf('error.IMPORT_INVALID_TIMEZONE', SURFACES)).toBe('sen');
    expect(surfaceOf('settings.quickBubbleSub', SURFACES)).toBe('sen');
  });
});

describe('toneProblems', () => {
  test('"siz" on a personal screen fails', () => {
    expect(
      toneProblems(
        { 'settings.quickBubbleSub': 'İstediğiniz yere sürükleyin', 'error.EXT_ONLY': 'x' },
        SURFACES,
      ),
    ).toEqual([
      { key: 'settings.quickBubbleSub', kind: 'siz-in-sen', words: ['istediğiniz', 'sürükleyin'] },
    ]);
  });

  test('"sen" on an extension screen fails', () => {
    const problems = toneProblems(
      { 'ee.tickets.new.pickService': 'Ne istiyorsun? Bir servis seç', 'error.EXT_ONLY': 'x' },
      SURFACES,
    );
    expect(problems).toEqual([
      { key: 'ee.tickets.new.pickService', kind: 'sen-in-siz', words: ['istiyorsun'] },
    ]);
  });

  test('one string with both fails on any surface', () => {
    const text = 'Ne istiyorsun? Bir servis seçin';
    for (const key of ['ee.x', 'task.x']) {
      expect(toneProblems({ [key]: text, 'error.EXT_ONLY': 'x' }, SURFACES)).toEqual([
        { key, kind: 'mixed', words: ['istiyorsun', 'seçin'] },
      ]);
    }
  });

  test('a listed key that no longer exists fails', () => {
    expect(toneProblems({ 'task.x': 'Sil' }, SURFACES)).toEqual([
      { key: 'error.EXT_ONLY', kind: 'stale-surface', words: [] },
    ]);
  });

  test('the right address on each surface passes', () => {
    expect(
      toneProblems(
        {
          'task.x': 'Saat seçmediğin görevlerin saati',
          'ee.x': 'Talep türünü seçin',
          'error.EXT_ONLY': 'Bu davet iptal edilmiş. Yöneticinizden yeni bir davet isteyin.',
        },
        SURFACES,
      ),
    ).toEqual([]);
  });
});

describe('licenceProblems', () => {
  test('"open source" and "açık kaynak" fail in either language', () => {
    expect(
      licenceProblems({
        en: { a: 'AllisWell is open source', b: 'Open-source app', c: 'Source-available' },
        tr: { a: 'AllisWell açık kaynak', b: 'Kaynak kodu erişilebilir' },
      }).map((p) => p.key),
    ).toEqual(['en:a', 'en:b', 'tr:a']);
  });
  test('a finding has the same shape as a tone finding, so the report can print it', () => {
    // Regression: the report read `words.length` and crashed on a licence finding.
    expect(licenceProblems({ en: { a: 'open source' } })).toEqual([
      { key: 'en:a', kind: 'open-source', words: [] },
    ]);
  });
});

describe('the shipped catalogues', () => {
  test('every Turkish string fits its surface, and no string says "open source"', () => {
    const tr = catalogue('tr');
    const en = catalogue('en');
    expect([...toneProblems(tr, loadSurfaces()), ...licenceProblems({ tr, en })]).toEqual([]);
  });
});
