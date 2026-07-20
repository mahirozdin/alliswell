import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { foldSearchText } from '../../src/lib/fold.js';

// ADR-0013: the JS fold and the Dart fold must be byte-identical. The fixture
// lives with the app (apps/app/test/fixtures/fold_parity.json) and both
// suites assert it — edit one implementation alone and a suite fails.
const fixture = JSON.parse(
  readFileSync(new URL('../../../app/test/fixtures/fold_parity.json', import.meta.url), 'utf8'),
);

describe('lib/fold (OPH-167, ADR-0013)', () => {
  it('matches the cross-stack parity fixture, pair by pair', () => {
    for (const [input, folded] of Object.entries(fixture.pairs)) {
      expect(foldSearchText(input), `fold(${JSON.stringify(input)})`).toBe(folded);
    }
  });

  it('is idempotent (folding folded text changes nothing)', () => {
    for (const folded of Object.values(fixture.pairs)) {
      expect(foldSearchText(folded)).toBe(folded);
    }
  });
});
