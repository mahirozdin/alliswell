/// The client-side context packer (OPH-221, AI.md §7) — a PURE function: its
/// inputs are plain lists (never a db handle), so it is fully unit-testable and
/// can never leak more than it is handed. It packs the minimum a request needs,
/// and the bubble's context chip shows exactly what came out.
///
/// Tiers: T0 locale/tz/now/default time/project names+counts (always) · T1
/// today+overdue+upcoming, TITLES only, ≤50 rows · T2 top-K fold-search
/// excerpts. Never packed: attachment bytes, presigned URLs, storage keys,
/// other members' data — the type system doesn't even accept them.
library;

class AiContextMeta {
  const AiContextMeta({
    required this.locale,
    required this.timezone,
    required this.nowIso,
    required this.weekday,
    required this.defaultTaskTime,
  });
  final String locale;
  final String timezone;
  final String nowIso;
  final String weekday;
  final String defaultTaskTime;
}

class ProjectLite {
  const ProjectLite({required this.id, required this.name, this.openCount = 0});
  final String id;
  final String name;
  final int openCount;
}

class TaskLite {
  const TaskLite({required this.title});
  final String title;
}

class SearchExcerpt {
  const SearchExcerpt({
    required this.source,
    required this.id,
    required this.text,
  });
  final String source; // task | note
  final String id;
  final String text;
}

class SharedPayload {
  const SharedPayload({required this.text, this.url});
  final String text;
  final String? url;
}

/// One packed segment. `source` names its provenance; the app never emits the
/// fence syntax — the server's lib/ai/context.js is the single renderer.
class AiContextSegment {
  const AiContextSegment({
    required this.tier,
    required this.source,
    this.id,
    required this.text,
  });
  final String tier; // t0 | t1 | t2
  final String source;
  final String? id;
  final String text;
  Map<String, dynamic> toJson() => {
    'tier': tier,
    'source': source,
    'id': ?id,
    'text': text,
  };
}

class AiContextBundle {
  const AiContextBundle({
    required this.segments,
    required this.tokenEstimate,
    required this.truncated,
  });
  final List<AiContextSegment> segments;
  final int tokenEstimate;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'segments': segments.map((s) => s.toJson()).toList(),
    'truncated': truncated,
  };
}

/// Rough token estimate — ~4 chars/token (documented heuristic; the server's
/// budget is generous enough that precision is not the point).
int estimateTokens(String text) => (text.length / 4).ceil();

const int _t1RowCap = 50;

AiContextBundle buildAiContext({
  required AiContextMeta meta,
  required List<ProjectLite> projects,
  List<TaskLite> today = const [],
  List<TaskLite> overdue = const [],
  List<TaskLite> upcoming = const [],
  List<SearchExcerpt> excerpts = const [],
  SharedPayload? sharedBlock,
  int tokenBudget = 6000,
}) {
  final segments = <AiContextSegment>[];
  var used = 0;
  var truncated = false;

  void add(AiContextSegment segment) {
    final cost = estimateTokens(segment.text);
    if (used + cost > tokenBudget) {
      truncated = true;
      return;
    }
    segments.add(segment);
    used += cost;
  }

  // T0 — always: the meta line and the project names/counts.
  add(
    AiContextSegment(
      tier: 't0',
      source: 'meta',
      text:
          'locale=${meta.locale} tz=${meta.timezone} now=${meta.nowIso} '
          'weekday=${meta.weekday} defaultTaskTime=${meta.defaultTaskTime}',
    ),
  );
  if (projects.isNotEmpty) {
    add(
      AiContextSegment(
        tier: 't0',
        source: 'projects',
        text: projects.map((p) => '${p.name} (${p.openCount})').join('\n'),
      ),
    );
  }

  // A shared block, when present, is framed as external content (strictest).
  if (sharedBlock != null) {
    add(
      AiContextSegment(
        tier: 't1',
        source: 'external_share',
        text: sharedBlock.url != null
            ? '${sharedBlock.url}\n${sharedBlock.text}'
            : sharedBlock.text,
      ),
    );
  }

  // T1 — today → overdue → upcoming, titles only, ≤50 rows total.
  final t1Titles = <String>[];
  for (final list in [today, overdue, upcoming]) {
    for (final task in list) {
      if (t1Titles.length >= _t1RowCap) {
        truncated = true;
        break;
      }
      t1Titles.add(task.title);
    }
  }
  if (t1Titles.isNotEmpty) {
    add(
      AiContextSegment(tier: 't1', source: 'task', text: t1Titles.join('\n')),
    );
  }

  // T2 — top-K excerpts until the budget runs out.
  for (final excerpt in excerpts) {
    add(
      AiContextSegment(
        tier: 't2',
        source: excerpt.source,
        id: excerpt.id,
        text: excerpt.text,
      ),
    );
  }

  return AiContextBundle(
    segments: segments,
    tokenEstimate: used,
    truncated: truncated,
  );
}
