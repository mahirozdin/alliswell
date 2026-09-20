import 'package:drift/drift.dart';

import '../core/fold.dart';
import '../sync/db/database.dart';

/// Local-first search (OPH-167, ADR-0013, DESIGN §12).
///
/// One SQL statement per domain over the `*_fold` shadow columns: tier 0 =
/// title/name, tier 1 = tag, tier 2 = body/description. Multi-word queries
/// AND their words (each word must appear SOMEWHERE in the entity's folded
/// text); the tier reflects the best single field that contains ALL words.
/// Everything runs inside SQLite's C loop — misses never materialize rows.
class SearchHit {
  const SearchHit({required this.id, required this.tier});

  final String id;

  /// 0 = title/name, 1 = tag, 2 = body/description.
  final int tier;
}

class SearchService {
  SearchService(this._db);

  final AwDatabase _db;

  /// Folded, deduped query words. Empty → the query matches nothing (callers
  /// treat '' as "search off", never "match all").
  static List<String> queryWords(String query) => foldSearchText(
    query,
  ).split(' ').where((w) => w.isNotEmpty).toSet().toList();

  static String _pattern(String word) =>
      '%${word.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  /// `field LIKE %w1% AND field LIKE %w2% …` — "this single field contains
  /// every word", the tier test.
  String _allWords(String field, List<String> words, List<Variable> vars) {
    final parts = <String>[];
    for (final word in words) {
      parts.add("$field LIKE ? ESCAPE '\\'");
      vars.add(Variable.withString(_pattern(word)));
    }
    return '(${parts.join(' AND ')})';
  }

  /// For each word: it appears in ANY of [fields] — the match test.
  String _eachWordSomewhere(
    List<String> fields,
    List<String> words,
    List<Variable> vars,
  ) {
    final perWord = <String>[];
    for (final word in words) {
      final anyField = <String>[];
      for (final field in fields) {
        anyField.add("$field LIKE ? ESCAPE '\\'");
        vars.add(Variable.withString(_pattern(word)));
      }
      perWord.add('(${anyField.join(' OR ')})');
    }
    return '(${perWord.join(' AND ')})';
  }

  /// Tasks of [statuses], ranked title > tag > description, then due date.
  Future<List<SearchHit>> searchTasks(
    String workspaceId,
    String query, {
    required List<String> statuses,
  }) async {
    if (statuses.isEmpty) return const [];
    return _run(
      _tasks,
      workspaceId,
      query,
      extraWhere:
          't.status IN (${List.filled(statuses.length, '?').join(', ')})',
      extraVars: [for (final s in statuses) Variable.withString(s)],
    );
  }

  /// The user's calendar events: summary (tier 0) and location (tier 2).
  Future<List<SearchHit>> searchEvents(String workspaceId, String query) =>
      _run(_events, workspaceId, query);

  /// Projects: name (tier 0) and description (tier 2).
  Future<List<SearchHit>> searchProjects(String workspaceId, String query) =>
      _run(_projects, workspaceId, query);

  /// The service desk's queue (EE-169): subject (tier 0), NUMBER (tier 1),
  /// body and replies (tier 2).
  ///
  /// The number is not a folded field and cannot be one. Folded text is a bag
  /// of words matched with LIKE '%…%', so searching `1042` there returns every
  /// request whose body happens to mention 1042 — an order number, a pressure,
  /// a year. A number is an IDENTIFIER: either this is the request somebody is
  /// holding or it is not.
  ///
  /// So a query that is a number is answered as a lookup FIRST, and the text
  /// search is what happens when the lookup misses. Returning both would put
  /// the request somebody asked for at the top of a list of coincidences, and
  /// a person reading a number off a mail subject is not browsing.
  Future<List<SearchHit>> searchTickets(
    String workspaceId,
    String query,
  ) async {
    final number = ticketNumberQuery(query);
    if (number != null) {
      final exact = await _db
          .customSelect(
            'SELECT id FROM tickets WHERE workspace_id = ? AND number = ?',
            variables: [
              Variable.withString(workspaceId),
              Variable.withInt(number),
            ],
          )
          .get();
      if (exact.isNotEmpty) {
        return [
          for (final row in exact)
            SearchHit(id: row.read<String>('id'), tier: 1),
        ];
      }
      // A miss falls through: the digits may well be in somebody's body text,
      // and answering "nothing" when the screen can see it would be a lie the
      // person cannot check.
    }
    return _run(_tickets, workspaceId, query);
  }

  /// EE-186 / OPH-327 — planned changes.
  ///
  /// Registered rather than special-cased, which is the whole point of the
  /// registry OPH-326 introduced: an extension's entity reads the same SQL
  /// shape and the same fold as the core domains. An entity outside search is
  /// an entity that does not exist for the person looking for it.
  Future<List<SearchHit>> searchChanges(String workspaceId, String query) =>
      _run(_changes, workspaceId, query);

  /// EE-188 / OPH-327 — known faults. The query somebody actually types here
  /// is the SYMPTOM ("printer jams after standby"), which is why that is the
  /// second tier and the root cause is in neither.
  Future<List<SearchHit>> searchProblems(String workspaceId, String query) =>
      _run(_problems, workspaceId, query);

  /// EE-191 / OPH-327 — the equipment register. The TAG is the first tier and
  /// the name is the second, which is the opposite of every other entity here:
  /// somebody standing at a machine reads the number off the sticker, and the
  /// name in the register is whatever the person who typed it called it.
  Future<List<SearchHit>> searchAssets(String workspaceId, String query) =>
      _run(_assets, workspaceId, query);

  /// One query for every entry in the registry, so the core domains and an
  /// extension's read the same SQL shape and the same fold.
  Future<List<SearchHit>> _run(
    SearchEntity entity,
    String workspaceId,
    String query, {
    String extraWhere = '',
    List<Variable> extraVars = const [],
  }) async {
    final words = queryWords(query);
    if (words.isEmpty) return const [];

    // CASE variables bind BEFORE the WHERE ones — order of appearance in SQL.
    final caseVars = <Variable>[];
    final tiers = entity.tiers.keys.toList()..sort();
    final cases = <String>[
      for (final tier in tiers.take(tiers.length - 1))
        'WHEN ${_allWords(entity.tiers[tier]!, words, caseVars)} THEN $tier',
    ];
    final whereVars = <Variable>[
      Variable.withString(workspaceId),
      ...extraVars,
    ];
    final match = _eachWordSomewhere(entity.fields, words, whereVars);

    final rows = await _db
        .customSelect(
          '''
SELECT ${entity.alias}.id AS id,
       CASE ${cases.join(' ')} ELSE ${tiers.last} END AS tier
FROM ${entity.table} ${entity.alias}
${entity.join}
WHERE ${entity.alias}.workspace_id = ?${extraWhere.isEmpty ? '' : ' AND $extraWhere'} AND $match
ORDER BY tier ASC, ${entity.order}
''',
          variables: [...caseVars, ...whereVars],
        )
        .get();
    return [
      for (final row in rows)
        SearchHit(id: row.read<String>('id'), tier: row.read<int>('tier')),
    ];
  }
}

/// `#1042` / `1042` → 1042, and anything else → null.
///
/// Deliberately strict: a query with any other word in it is a text search,
/// not a lookup. "1042 pompa" means "find the pump one, I think it was 1042",
/// and answering with request 1042 alone would drop the half the person
/// actually typed.
int? ticketNumberQuery(String query) {
  final trimmed = query.trim();
  final digits = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (digits.isEmpty || digits.length > 9) return null;
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
  final value = int.tryParse(digits);
  return value == null || value <= 0 ? null : value;
}

/// OPH-326 — WHAT IS SEARCHABLE, as data.
///
/// Before this there were three hand-written statements that differed only in
/// their table, their columns and their ordering — and an extension with its
/// own entity had no way in except a fourth copy. A copy is not only more code:
/// it is a second definition of "matches", and the one thing ADR-0013 does not
/// survive is two of those.
///
/// An entry is (table, alias, tier → folded expression), plus the two things
/// that genuinely differ per entity: an extra JOIN for text that lives in
/// another table, and the tie-break order inside a tier. The HIGHEST tier is
/// the `ELSE` — every row that matched at all lands there — so an entry needs
/// at least two.
class SearchEntity {
  const SearchEntity({
    required this.table,
    required this.alias,
    required this.tiers,
    required this.order,
    this.join = '',
  });

  final String table;
  final String alias;

  /// tier → the folded SQL expression that earns it. Lowest wins.
  final Map<int, String> tiers;

  /// The tie-break INSIDE a tier; `tier ASC` always comes first.
  final String order;

  /// Optional join supplying an expression the tiers refer to.
  final String join;

  /// Every expression, for the "did this row match at all" test.
  List<String> get fields => tiers.values.toList();
}

const _tasks = SearchEntity(
  table: 'tasks',
  alias: 't',
  tiers: {
    0: "IFNULL(t.title_fold, '')",
    1: "IFNULL(agg.tags_fold, '')",
    2: "IFNULL(t.description_fold, '')",
  },
  join: '''
LEFT JOIN (
  SELECT tt.task_id AS task_id, GROUP_CONCAT(g.name_fold, ' ') AS tags_fold
  FROM task_tag_rows tt JOIN tags g ON g.id = tt.tag_id
  GROUP BY tt.task_id
) agg ON agg.task_id = t.id''',
  order: 't.due_at IS NULL ASC, t.due_at ASC, t.id DESC',
);

const _events = SearchEntity(
  table: 'external_events',
  alias: 'e',
  tiers: {0: "IFNULL(e.summary_fold, '')", 2: "IFNULL(e.location_fold, '')"},
  order: 'e.starts_at ASC',
);

const _projects = SearchEntity(
  table: 'projects',
  alias: 'p',
  tiers: {0: "IFNULL(p.name_fold, '')", 2: "IFNULL(p.description_fold, '')"},
  order: 'p.sort_order ASC, p.id DESC',
);

/// EE-169. The replies join the way tags do — one concatenated blob per
/// request — because a request is what the person is looking for, and a list
/// of matching REPLIES would be a list of fragments they then have to trace
/// back. Internal notes are in that blob on purpose: everybody holding this
/// replica is an agent, and the note was written for them (ADR-0011 §3).
const _tickets = SearchEntity(
  table: 'tickets',
  alias: 'k',
  tiers: {
    0: "IFNULL(k.subject_fold, '')",
    2: "IFNULL(k.body_fold, '') || ' ' || IFNULL(cmt.body_fold, '')",
  },
  join: '''
LEFT JOIN (
  SELECT c.ticket_id AS ticket_id, GROUP_CONCAT(c.body_fold, ' ') AS body_fold
  FROM ticket_comments c
  GROUP BY c.ticket_id
) cmt ON cmt.ticket_id = k.id''',
  order: 'k.created_at DESC, k.id DESC',
);

/// EE-186. The title is what somebody searches for; the impact text is what
/// they search for when they cannot remember the title. The rollback plan is
/// deliberately NOT searchable: it is the field somebody reads in full before
/// acting, and surfacing it as a fragment would invite acting on the fragment.
const _changes = SearchEntity(
  table: 'changes',
  alias: 'g',
  tiers: {0: "IFNULL(g.title_fold, '')", 2: "IFNULL(g.impact_fold, '')"},
  order: 'g.window_start IS NULL, g.window_start ASC, g.created_at DESC',
);

/// EE-188. Title first, symptom second, root cause nowhere: a person looking
/// for a known error is describing what they SEE, and matching on the
/// diagnosis would rank the records whose cause happens to share a word with
/// the thing they are looking at.
const _problems = SearchEntity(
  table: 'problems',
  alias: 'b',
  tiers: {0: "IFNULL(b.title_fold, '')", 2: "IFNULL(b.symptom_fold, '')"},
  order: "b.status = 'closed', b.created_at DESC",
);

/// EE-191. Tag first, name second. A retired machine sorts last rather than
/// disappearing: the reason somebody searches for a scrapped asset is to read
/// what happened to it, and a register that hides its own history answers the
/// question "did we already replace this" with silence.
const _assets = SearchEntity(
  table: 'assets',
  alias: 'v',
  tiers: {0: "IFNULL(v.tag_fold, '')", 1: "IFNULL(v.name_fold, '')"},
  order: "v.status = 'retired', v.name ASC",
);

/// A short window of [original] around the first folded match of [word] —
/// the honest "WHERE it hit" context line (DESIGN S3). The fold is nearly
/// length-preserving (only ß/æ/œ expand), so the folded index maps back onto
/// the original within a character or two — good enough for a snippet.
String searchSnippet(String original, String word, {int radius = 32}) {
  final folded = foldSearchText(original);
  final index = folded.indexOf(foldSearchText(word));
  if (index < 0) {
    return original.length <= radius * 2
        ? original
        : '${original.substring(0, radius * 2)}…';
  }
  final start = (index - radius).clamp(0, original.length);
  final end = (index + word.length + radius).clamp(0, original.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < original.length ? '…' : '';
  return '$prefix${original.substring(start, end).trim()}$suffix';
}
