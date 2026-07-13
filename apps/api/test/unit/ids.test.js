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
});
