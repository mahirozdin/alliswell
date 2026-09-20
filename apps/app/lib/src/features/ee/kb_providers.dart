import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/providers.dart';
import '../../search/search.dart';
import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/kb_api.dart';
import 'data/kb_models.dart';
import 'providers.dart';

/// The knowledge base (EE-195, EE-196).
///
/// ── TWO SOURCES, AND THE SPLIT IS NOT ARBITRARY ────────────────────────
///
/// WRITING goes to the server: authoring, the lifecycle and the counters all
/// live there, and none of them can be done offline by design (`kb.publish`
/// exists precisely so a sentence reaches customers only after a person
/// decided it should).
///
/// READING AND SEARCHING come off the REPLICA. That is the half EE-195's
/// task asked for in one sentence — "the agent has to be able to look the
/// solution up in the field" — and it is why `check:no-server-search` exists:
/// a screen half-drawn from a replica and half from a request answers "no
/// results" and "no network" with the same empty list, and a person cannot
/// tell them apart.
final eeKbApiProvider = Provider<EeKbApi>(
  (ref) => EeKbApi(ref.watch(apiClientProvider)),
);

/// The list screen's status filter. A `Notifier` rather than a
/// `StateProvider`, which this Riverpod does not have — the house pattern is
/// `TicketFilterController` (`tickets_providers.dart:113`).
class KbStatusFilter extends Notifier<String?> {
  @override
  String? build() => null;

  /// Tapping the selected chip clears it: a filter you cannot turn off from
  /// the same tap that turned it on is a filter people work around.
  void toggle(String status) => state = state == status ? null : status;

  void clear() => state = null;
}

final eeKbStatusFilterProvider = NotifierProvider<KbStatusFilter, String?>(
  KbStatusFilter.new,
);

/// The articles, from the DEVICE.
///
/// A drift watch rather than a future: an article published on somebody
/// else's screen should appear here on the next pull without the reader
/// touching anything, and a list that froze at its first read would disagree
/// with the search field sitting above it.
final eeKbArticlesProvider = StreamProvider<List<KbArticleRecord>>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const <KbArticleRecord>[]);
  final db = ref.watch(databaseProvider);
  final status = ref.watch(eeKbStatusFilterProvider);
  final query = db.select(db.kbArticles)
    ..where((a) => a.workspaceId.equals(workspace.id));
  if (status != null) query.where((a) => a.status.equals(status));
  // WIP first, then newest. The task's reason: an article sitting in WIP for
  // weeks is list pollution and the screen has to SHOW it — a list that
  // buried them under published answers would hide the one thing that status
  // exists to make visible.
  query.orderBy([
    (a) => OrderingTerm(
      expression: a.status.equals('wip'),
      mode: OrderingMode.desc,
    ),
    (a) => OrderingTerm(expression: a.updatedAt, mode: OrderingMode.desc),
  ]);
  return query.watch();
});

/// One article, watched: a status change pushed from another device redraws
/// the open card rather than leaving a stale header on screen.
final eeKbArticleProvider = StreamProvider.family<KbArticleRecord?, String>((
  ref,
  articleId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.kbArticles,
  )..where((a) => a.id.equals(articleId))).watchSingleOrNull();
});

/// The search field's text, per screen (DESIGN S5).
final eeKbSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Ranked ids, or null when search is off.
///
/// Reads the REPLICA through the registry OPH-326 introduced, so it answers
/// with no signal — and so an article whose title is `Yazıcı` is found by
/// somebody typing `yazici`, which neither SQLite nor MySQL would do on its
/// own (ADR-0013: the `ı`/`i` fold is app-owned).
final eeKbSearchResultsProvider = FutureProvider.autoDispose<List<SearchHit>?>((
  ref,
) async {
  final query = ref.watch(eeKbSearchQueryProvider).trim();
  if (query.isEmpty) return null;
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  // Rebuild when the list does, so a newly pulled article can be found by a
  // field that is already open.
  ref.watch(eeKbArticlesProvider);
  return ref.watch(searchServiceProvider).searchKbArticles(workspace.id, query);
});

/// EE-196 — the articles that match a request, shown while somebody works it.
///
/// ── THIS IS ASSISTANCE, NOT DEFLECTION, AND THE NAMES SAY SO ───────────
///
/// The task's own sentence is that an article shown BEFORE a request is
/// opened is a different thing from one shown after: the first prevents a
/// request, the second helps answer one. Only the first is deflection, and
/// only the first moves a counter.
///
/// This is the second. It is measured against a request that ALREADY EXISTS,
/// so it deliberately increments nothing — a counter fed from here would
/// report deflections that never happened and make the desk look better the
/// more requests it received. The deflection half belongs to the portal
/// (EE-197), where somebody really is about to ask.
///
/// It is not a server call for the reason above the file: the request's
/// subject is already on this device, and so are the articles.
final eeKbSuggestionsProvider = FutureProvider.autoDispose
    .family<List<KbArticleRecord>, String>((ref, subject) async {
      if (subject.trim().isEmpty) return const [];
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return const [];
      final hits = await ref
          .watch(searchServiceProvider)
          .searchKbArticles(workspace.id, subject);
      if (hits.isEmpty) return const [];
      final db = ref.watch(databaseProvider);
      final rows =
          await (db.select(db.kbArticles)
                ..where((a) => a.id.isIn(hits.map((h) => h.id).toList()))
                // PUBLISHED only. Offering an unreviewed draft as "the answer
                // to this" is the thing `kb.publish` exists to prevent, and a
                // suggestion list is exactly where somebody would copy it into
                // a reply without reading the status chip.
                ..where((a) => a.status.equals('published')))
              .get();
      // Ranked the way the search ranked them, not the way SQL returned them.
      final order = {for (var i = 0; i < hits.length; i += 1) hits[i].id: i};
      rows.sort(
        (a, b) => (order[a.id] ?? 1 << 30).compareTo(order[b.id] ?? 1 << 30),
      );
      return rows.take(3).toList(growable: false);
    });

/// What this request has already produced (EE-196). From the SERVER: an
/// article born of a request may live in another workspace's stream, and the
/// device only carries the ones it pulls.
final eeKbOfTicketProvider = FutureProvider.autoDispose
    .family<List<EeKbArticle>, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      return ref.watch(eeKbApiProvider).ofTicket(ticketId);
    });
