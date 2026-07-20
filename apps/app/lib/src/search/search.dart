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
    final words = queryWords(query);
    if (words.isEmpty || statuses.isEmpty) return const [];
    final vars = <Variable>[];
    const title = "IFNULL(t.title_fold, '')";
    const description = "IFNULL(t.description_fold, '')";
    const tags = "IFNULL(agg.tags_fold, '')";
    final titleAll = _allWords(title, words, vars);
    final tagsAll = _allWords(tags, words, vars);
    // WHERE variables come AFTER the CASE ones — order of appearance in SQL.
    final whereVars = <Variable>[Variable.withString(workspaceId)];
    final statusMarks = List.filled(statuses.length, '?').join(', ');
    whereVars.addAll([for (final s in statuses) Variable.withString(s)]);
    final match = _eachWordSomewhere(
      [title, description, tags],
      words,
      whereVars,
    );
    final rows = await _db
        .customSelect(
          '''
SELECT t.id AS id,
       CASE WHEN $titleAll THEN 0 WHEN $tagsAll THEN 1 ELSE 2 END AS tier
FROM tasks t
LEFT JOIN (
  SELECT tt.task_id AS task_id, GROUP_CONCAT(g.name_fold, ' ') AS tags_fold
  FROM task_tag_rows tt JOIN tags g ON g.id = tt.tag_id
  GROUP BY tt.task_id
) agg ON agg.task_id = t.id
WHERE t.workspace_id = ? AND t.status IN ($statusMarks) AND $match
ORDER BY tier ASC, t.due_at IS NULL ASC, t.due_at ASC, t.id DESC
''',
          variables: [...vars, ...whereVars],
        )
        .get();
    return [
      for (final row in rows)
        SearchHit(id: row.read<String>('id'), tier: row.read<int>('tier')),
    ];
  }

  /// The user's calendar events: summary (tier 0) and location (tier 2).
  Future<List<SearchHit>> searchEvents(String workspaceId, String query) async {
    final words = queryWords(query);
    if (words.isEmpty) return const [];
    final vars = <Variable>[];
    const summary = "IFNULL(e.summary_fold, '')";
    const location = "IFNULL(e.location_fold, '')";
    final summaryAll = _allWords(summary, words, vars);
    final whereVars = <Variable>[Variable.withString(workspaceId)];
    final match = _eachWordSomewhere([summary, location], words, whereVars);
    final rows = await _db
        .customSelect(
          '''
SELECT e.id AS id, CASE WHEN $summaryAll THEN 0 ELSE 2 END AS tier
FROM external_events e
WHERE e.workspace_id = ? AND $match
ORDER BY tier ASC, e.starts_at ASC
''',
          variables: [...vars, ...whereVars],
        )
        .get();
    return [
      for (final row in rows)
        SearchHit(id: row.read<String>('id'), tier: row.read<int>('tier')),
    ];
  }

  /// Projects: name (tier 0) and description (tier 2).
  Future<List<SearchHit>> searchProjects(
    String workspaceId,
    String query,
  ) async {
    final words = queryWords(query);
    if (words.isEmpty) return const [];
    final vars = <Variable>[];
    const name = "IFNULL(p.name_fold, '')";
    const description = "IFNULL(p.description_fold, '')";
    final nameAll = _allWords(name, words, vars);
    final whereVars = <Variable>[Variable.withString(workspaceId)];
    final match = _eachWordSomewhere([name, description], words, whereVars);
    final rows = await _db
        .customSelect(
          '''
SELECT p.id AS id, CASE WHEN $nameAll THEN 0 ELSE 2 END AS tier
FROM projects p
WHERE p.workspace_id = ? AND $match
ORDER BY tier ASC, p.sort_order ASC, p.id DESC
''',
          variables: [...vars, ...whereVars],
        )
        .get();
    return [
      for (final row in rows)
        SearchHit(id: row.read<String>('id'), tier: row.read<int>('tier')),
    ];
  }
}

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
