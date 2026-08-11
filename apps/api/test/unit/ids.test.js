import { describe, it, expect } from 'vitest';
import { newId } from '../../src/lib/ids.js';

describe('newId', () => {
  it('generates 26-char Crockford base32 ULIDs', () => {
    const id = newId();
    expect(id).toHaveLength(26);
    expect(id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/);
  });

  it('generates unique, time-sortable ids', () => {
    const ids = Array.from({ length: 1000 }, () => newId());
    expect(new Set(ids).size).toBe(1000);
  });

  // OPH-248 — "time-sortable" above was a claim, not a guarantee.
  //
  // Plain `ulid()` re-rolls its random component on every call, so two ids
  // minted in the SAME millisecond sort by chance. Lists across the app page
  // with `orderBy('id', 'desc')` (notes, tasks, files), which made that a real
  // ordering bug: `notes.test.js`'s "lists newest-first" case failed about one
  // run in three, and a user creating two notes quickly could see them the
  // wrong way round with nothing to explain it.
  it('is monotonic within a millisecond, not merely unique', () => {
    // Thousands of ids in far less than a millisecond — precisely the case the
    // original test could not distinguish, because uniqueness holds either way.
    const ids = Array.from({ length: 5000 }, () => newId());

    expect(ids).toEqual([...ids].sort());
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('sorts newest-last, so `order by id desc` really is newest-first', () => {
    const first = newId();
    const second = newId();

    expect(second > first).toBe(true);
  });
});
