import { foldSearchText } from '../fold.js';

/**
 * Project-name resolution (OPH-219, AI.md §4): "project matching is ours, not
 * the model's". The model returns `projectName` verbatim; THIS maps it onto
 * real projects with the ADR-0013 Turkish fold and three tiers in order:
 *
 *   exact     folded name === folded query
 *   prefix    folded name starts with the folded query
 *   contains  folded name contains the folded query
 *
 * The first non-empty tier defines the candidates. Exactly one candidate →
 * a match (the confirm card preselects / MCP creates); more or zero → the
 * card shows a picker + "+ Proje ekle", MCP declines to create.
 *
 * Byte-for-byte parity with the Dart twin
 * (apps/app/lib/src/features/ai/data/project_match.dart, OPH-222) is pinned
 * by the shared fixture apps/app/test/fixtures/project_match_parity.json —
 * the fold_parity.json pattern.
 */

/**
 * @param {string} projectName the user's words
 * @param {Array<{id: string, name: string}>} projects live projects
 * @returns {{tier: 'exact'|'prefix'|'contains'|'none', match: {id, name}|null, candidates: Array<{id, name}>}}
 */
export function matchProject(projectName, projects) {
  const query = foldSearchText(projectName ?? '');
  if (!query) return { tier: 'none', match: null, candidates: [] };

  const folded = projects.map((project) => ({
    project,
    folded: foldSearchText(project.name ?? ''),
  }));

  const tiers = [
    ['exact', ({ folded: name }) => name === query],
    ['prefix', ({ folded: name }) => name.startsWith(query)],
    ['contains', ({ folded: name }) => name.includes(query)],
  ];

  for (const [tier, test] of tiers) {
    const hits = folded.filter(test).map(({ project }) => project);
    if (hits.length > 0) {
      return { tier, match: hits.length === 1 ? hits[0] : null, candidates: hits };
    }
  }
  return { tier: 'none', match: null, candidates: [] };
}
