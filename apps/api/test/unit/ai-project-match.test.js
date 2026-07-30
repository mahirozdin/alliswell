import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, it, expect } from 'vitest';
import { matchProject } from '../../src/lib/ai/project-match.js';

/**
 * OPH-219 — the JS half of the project-match parity pair. The Dart twin
 * (apps/app/test/features/ai/project_match_test.dart, OPH-222) runs the SAME
 * fixture; change one side alone and the other fails (the fold_parity model).
 */

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../app/test/fixtures/project_match_parity.json',
);
const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

const projects = fixture.projects.map((name, index) => ({ id: `P${index}`, name }));
const byName = new Map(projects.map((p) => [p.name, p]));

describe('matchProject parity fixture', () => {
  for (const testCase of fixture.cases) {
    it(`"${testCase.query}" → ${testCase.tier} (${testCase.note})`, () => {
      const result = matchProject(testCase.query, projects);
      expect(result.tier).toBe(testCase.tier);
      expect(result.candidates.map((c) => c.name)).toEqual(testCase.candidates);
      if (testCase.match === null) {
        expect(result.match).toBeNull();
      } else {
        expect(result.match).toEqual(byName.get(testCase.match));
      }
    });
  }
});

describe('matchProject semantics beyond the fixture', () => {
  it('tier precedence: an exact hit hides prefix hits', () => {
    const result = matchProject('Okul', projects);
    expect(result.tier).toBe('exact');
    expect(result.candidates.map((c) => c.name)).toEqual(['Okul']);
  });

  it('candidate order is the input project order (stable for the picker)', () => {
    const result = matchProject('ok', projects);
    expect(result.candidates.map((c) => c.name)).toEqual(['Okul', 'okuma listesi']);
  });

  it('handles empty inputs without throwing', () => {
    expect(matchProject('', projects)).toEqual({ tier: 'none', match: null, candidates: [] });
    expect(matchProject('x', [])).toEqual({ tier: 'none', match: null, candidates: [] });
    expect(matchProject(null, projects).tier).toBe('none');
  });
});
