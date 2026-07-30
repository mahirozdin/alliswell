import '../../../core/fold.dart';

/// Project-name resolution (OPH-222) — the Dart twin of the API's
/// lib/ai/project-match.js. The model returns `projectName` verbatim; this maps
/// it onto real projects with the ADR-0013 fold and three tiers in order:
/// exact → prefix → contains. The first non-empty tier defines the candidates;
/// exactly one candidate is a match (the confirm card preselects it).
///
/// Byte-for-byte parity with the JS side is pinned by the shared fixture
/// test/fixtures/project_match_parity.json — the fold_parity.json pattern.

class ProjectMatch {
  const ProjectMatch({
    required this.tier,
    required this.match,
    required this.candidates,
  });
  final String tier; // exact | prefix | contains | none
  final ProjectRef? match;
  final List<ProjectRef> candidates;
}

class ProjectRef {
  const ProjectRef({required this.id, required this.name});
  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ProjectRef && other.id == id && other.name == name;
  @override
  int get hashCode => Object.hash(id, name);
}

ProjectMatch matchProject(String? projectName, List<ProjectRef> projects) {
  final query = foldSearchText(projectName ?? '');
  if (query.isEmpty) {
    return const ProjectMatch(tier: 'none', match: null, candidates: []);
  }

  final folded = [
    for (final p in projects) (project: p, folded: foldSearchText(p.name)),
  ];

  final tiers = <(String, bool Function(String))>[
    ('exact', (name) => name == query),
    ('prefix', (name) => name.startsWith(query)),
    ('contains', (name) => name.contains(query)),
  ];

  for (final (tier, test) in tiers) {
    final hits = [
      for (final f in folded)
        if (test(f.folded)) f.project,
    ];
    if (hits.isNotEmpty) {
      return ProjectMatch(
        tier: tier,
        match: hits.length == 1 ? hits.first : null,
        candidates: hits,
      );
    }
  }
  return const ProjectMatch(tier: 'none', match: null, candidates: []);
}
