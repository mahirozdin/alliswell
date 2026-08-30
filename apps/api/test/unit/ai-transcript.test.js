import { describe, expect, it } from 'vitest';

import {
  groupWordsBySpeaker,
  normalizeTranscript,
  secondsToMs,
} from '../../src/lib/ai/transcript.js';
import { AI_PROVIDERS, AI_USAGE_PROVIDERS } from '../../src/lib/ai/vendors.js';
import { providers } from '../../src/lib/ai/providers/index.js';

/**
 * The one transcript shape, and the refusals that keep it one.
 *
 * The adapters' own suites prove that three vendors converge on this shape.
 * This file proves the other half: that converging is CHECKED rather than
 * hoped for. A normalizer that repaired bad input instead of refusing it
 * would let a parsing bug in an adapter reach a screen as a transcript with a
 * segment that ends before it starts.
 */

const seg = (over = {}) => ({ speaker: 'A', startMs: 0, endMs: 1000, text: 'merhaba', ...over });

describe('normalizeTranscript', () => {
  it('derives the speaker list from the segments rather than trusting a count', () => {
    const out = normalizeTranscript({
      segments: [
        seg(),
        seg({ speaker: 'B', startMs: 1000, endMs: 2000 }),
        seg({ startMs: 2000, endMs: 3000 }),
      ],
    });
    expect(out.speakers).toEqual(['A', 'B']);
  });

  it('sorts by start time — assembled utterances can arrive out of order', () => {
    const out = normalizeTranscript({
      segments: [
        seg({ startMs: 5000, endMs: 6000, text: 'sonra' }),
        seg({ startMs: 0, endMs: 1000, text: 'önce' }),
      ],
    });
    expect(out.segments.map((s) => s.text)).toEqual(['önce', 'sonra']);
  });

  it('falls back to the end of the last utterance when no duration was reported', () => {
    const out = normalizeTranscript({ segments: [seg({ endMs: 4321 })] });
    expect(out.durationMs).toBe(4321);
  });

  it('keeps a reported duration, rounded to whole milliseconds', () => {
    const out = normalizeTranscript({ segments: [seg()], durationMs: 12500.4 });
    expect(out.durationMs).toBe(12500);
  });

  it.each([
    ['a speaker that is not a string', { speaker: 0 }, /speaker must be/],
    ['an empty speaker', { speaker: '' }, /speaker must be/],
    ['a missing bound', { endMs: undefined }, /finite numbers/],
    ['a NaN bound', { startMs: Number.NaN }, /finite numbers/],
    ['a negative start', { startMs: -1 }, /non-negative/],
    ['an end before its start', { startMs: 900, endMs: 100 }, /at or after it starts/],
    ['empty text', { text: '   ' }, /text must be/],
  ])('refuses %s', (_name, override, message) => {
    expect(() => normalizeTranscript({ segments: [seg(override)] })).toThrow(message);
  });

  it('refuses segments that are not an array at all', () => {
    expect(() => normalizeTranscript({ segments: null })).toThrow(/must be an array/);
  });

  it('trims text, because a stray newline is a row that looks broken', () => {
    const out = normalizeTranscript({ segments: [seg({ text: '  merhaba\n' })] });
    expect(out.segments[0].text).toBe('merhaba');
  });
});

describe('groupWordsBySpeaker', () => {
  const word = (text, speaker, startMs, endMs) => ({ speaker, startMs, endMs, text });

  it('starts a new utterance when the speaker changes, and only then', () => {
    const out = groupWordsBySpeaker([
      word('bir', '0', 0, 100),
      word('iki', '0', 100, 200),
      word('üç', '1', 200, 300),
      word('dört', '0', 300, 400),
    ]);
    expect(out.map((s) => s.text)).toEqual(['bir iki', 'üç', 'dört']);
    expect(out[0]).toMatchObject({ startMs: 0, endMs: 200 });
  });

  it('does not split on a long pause — that is a display preference', () => {
    // Two adapters reading the same audio must not disagree about how many
    // segments there are, so no threshold is baked in here.
    const out = groupWordsBySpeaker([word('bir', '0', 0, 100), word('iki', '0', 60000, 60100)]);
    expect(out).toHaveLength(1);
  });

  it('is empty for no words rather than throwing', () => {
    expect(groupWordsBySpeaker([])).toEqual([]);
  });
});

describe('secondsToMs', () => {
  it('rounds to whole milliseconds so a timeline holds integers', () => {
    expect(secondsToMs(4.2)).toBe(4200);
    expect(secondsToMs(0.0001)).toBe(0);
  });
});

describe('the vendor lists', () => {
  it('meters a superset of what it can connect to', () => {
    for (const name of AI_PROVIDERS) expect(AI_USAGE_PROVIDERS).toContain(name);
    expect(AI_USAGE_PROVIDERS.length).toBeGreaterThan(AI_PROVIDERS.length);
  });

  it('keeps transcription-only vendors OUT of the connectable list', () => {
    // A settings screen offering one would be offering a provider that fails
    // at the first message: there is no adapter for it in core's registry.
    for (const name of AI_USAGE_PROVIDERS) {
      if (AI_PROVIDERS.includes(name)) continue;
      expect(providers[name], name).toBeUndefined();
    }
  });

  it('has an adapter for every connectable vendor', () => {
    for (const name of AI_PROVIDERS) expect(typeof providers[name]?.chatStream).toBe('function');
  });
});
