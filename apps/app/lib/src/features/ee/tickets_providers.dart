// The whole surface, not a `show` list: the join predicate below uses
// drift's `&` on Expression<bool>, which is an extension the narrowed import
// does not carry.
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../search/providers.dart';
import '../../search/search.dart';
import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'assignments_providers.dart' show Assignee;

/// The unit's queue, read from the REPLICA (EE-084, D5).
///
/// Everything here watches drift rather than calling the server, and that is
/// the entire point of the epic: the desk opens on a factory floor with no
/// signal. A provider that fetched over HTTP would be correct in the office
/// and useless in the plant — which is where the product is sold.
///
/// The scope is the CURRENT workspace, and that is a limit rather than an
/// oversight: the sync engine runs one workspace at a time (measured in E08,
/// recorded again in ADR-0011 §3), so a queue spanning units would show rows
/// as stale as the last visit. Showing that would be silently WRONG; scoping
/// is silently INCOMPLETE, and incomplete is the better failure.

/// What the queue is filtered by. Immutable so a rebuild cannot half-apply one.
/// EE-171 — who is on it, as a filter.
///
/// `mine` and `unassigned` are not "a person filter with a special id": they
/// are the two questions a desk actually asks, and the second one is the
/// expensive one — a queue's costliest state is work nobody has picked up, and
/// it is invisible until something asks for it.
enum TicketAssigneeScope { any, mine, unassigned, person }

class TicketFilter {
  const TicketFilter({
    this.statuses = const {},
    this.priorities = const {},
    this.serviceId,
    this.assigneeScope = TicketAssigneeScope.any,
    this.assigneeId,
    this.slaStatuses = const {},
    this.sources = const {},
    this.from,
    this.to,
  });

  /// Empty means "no filter", NOT "nothing" — the distinction the screen's
  /// chips rely on, and the one an `isEmpty` check gets wrong in the other
  /// direction if the default were "all statuses selected".
  final Set<String> statuses;
  final Set<String> priorities;
  final String? serviceId;

  /// EE-171: who is on it. `person` carries [assigneeId]; the other three do not.
  final TicketAssigneeScope assigneeScope;
  final String? assigneeId;

  /// `met` · `ok` · `warned` · `breached` — the badge EE-097 puts on the row.
  final Set<String> slaStatuses;

  /// `internal` · `public` · `health` · `sla` — where the request came from.
  final Set<String> sources;

  /// Filed within this window. Inclusive at both ends, day-resolution: the
  /// person picking "last week" means the whole of both days.
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      statuses.isEmpty &&
      priorities.isEmpty &&
      serviceId == null &&
      assigneeScope == TicketAssigneeScope.any &&
      slaStatuses.isEmpty &&
      sources.isEmpty &&
      from == null &&
      to == null;

  TicketFilter copyWith({
    Set<String>? statuses,
    Set<String>? priorities,
    String? serviceId,
    bool clearService = false,
    TicketAssigneeScope? assigneeScope,
    String? assigneeId,
    Set<String>? slaStatuses,
    Set<String>? sources,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) {
    final scope = assigneeScope ?? this.assigneeScope;
    return TicketFilter(
      statuses: statuses ?? this.statuses,
      priorities: priorities ?? this.priorities,
      serviceId: clearService ? null : (serviceId ?? this.serviceId),
      assigneeScope: scope,
      // The id belongs to `person` and to no other scope. Keeping a stale one
      // behind "anybody" is exactly the invisible filter DESIGN §16 refuses.
      assigneeId: scope == TicketAssigneeScope.person
          ? (assigneeId ?? this.assigneeId)
          : null,
      slaStatuses: slaStatuses ?? this.slaStatuses,
      sources: sources ?? this.sources,
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
    );
  }
}

final ticketFilterProvider =
    NotifierProvider<TicketFilterController, TicketFilter>(
      TicketFilterController.new,
    );

class TicketFilterController extends Notifier<TicketFilter> {
  @override
  TicketFilter build() => const TicketFilter();

  void toggleStatus(String status) =>
      state = state.copyWith(statuses: _toggled(state.statuses, status));

  void togglePriority(String priority) =>
      state = state.copyWith(priorities: _toggled(state.priorities, priority));

  void setService(String? serviceId) => state = state.copyWith(
    serviceId: serviceId,
    clearService: serviceId == null,
  );

  /// EE-171. One call for all four scopes so the screen cannot build an
  /// impossible one (a `person` with no id, or an id with scope `any`).
  void setAssignee(TicketAssigneeScope scope, {String? userId}) =>
      state = state.copyWith(
        assigneeScope: scope,
        assigneeId: scope == TicketAssigneeScope.person ? userId : null,
      );

  void toggleSlaStatus(String status) =>
      state = state.copyWith(slaStatuses: _toggled(state.slaStatuses, status));

  void toggleSource(String source) =>
      state = state.copyWith(sources: _toggled(state.sources, source));

  /// Both ends at once: a range with one end is a range the person is still
  /// typing, and applying it halfway would empty the list under their hands.
  void setRange(DateTime? from, DateTime? to) => state = state.copyWith(
    from: from,
    to: to,
    clearDates: from == null && to == null,
  );

  void clear() => state = const TicketFilter();

  static Set<String> _toggled(Set<String> from, String value) {
    final next = {...from};
    if (!next.remove(value)) next.add(value);
    return next;
  }
}

/// Every ticket in this workspace, newest first — the unfiltered truth.
///
/// The filter is applied in Dart rather than in the query, and deliberately:
/// a unit's whole queue is the thing ADR-0011 sized (a few thousand rows at
/// the archive window), the chips change on every tap, and re-preparing a
/// statement per keystroke buys nothing against a list that small. If a
/// measurement ever says otherwise, the place to fix it is here and the shape
/// above does not have to change.
final ticketQueueProvider = StreamProvider<List<TicketRecord>>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const <TicketRecord>[]);
  final db = ref.watch(databaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.workspaceId.equals(workspace.id))
        ..orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
          // A tiebreak the clock cannot give: two tickets filed in the same
          // millisecond would otherwise swap places between rebuilds.
          (t) => OrderingTerm.desc(t.id),
        ]))
      .watch();
});

/// The queue as the screen draws it: filtered, and with the terminal ones last.
final filteredTicketsProvider = Provider<AsyncValue<List<TicketRecord>>>((ref) {
  final filter = ref.watch(ticketFilterProvider);
  // EE-169: null = search off. A query that is still running narrows to
  // nothing rather than showing the unfiltered queue for a frame — a list that
  // flashes the wrong rows is worse than one that arrives a moment later.
  final search = ref.watch(ticketSearchResultsProvider);
  final hits = search.value;
  final searching = ref.watch(ticketSearchQueryProvider).trim().isNotEmpty;
  // EE-171: who is on each request, and who I am. Both are watched rather than
  // read so a newly-assigned row leaves a "kimseye atanmamış" list the moment
  // somebody picks it up.
  final assignees =
      ref.watch(ticketAssigneesProvider).value ??
      const <String, List<Assignee>>{};
  final me = ref.watch(currentUserIdProvider);
  final rank = hits == null
      ? null
      : {for (final (i, hit) in hits.indexed) hit.id: i};
  return ref.watch(ticketQueueProvider).whenData((rows) {
    final kept = rows.where((t) {
      if (filter.statuses.isNotEmpty && !filter.statuses.contains(t.status)) {
        return false;
      }
      if (filter.priorities.isNotEmpty &&
          !filter.priorities.contains(t.priority)) {
        return false;
      }
      if (filter.serviceId != null && t.serviceId != filter.serviceId) {
        return false;
      }
      if (filter.slaStatuses.isNotEmpty &&
          !filter.slaStatuses.contains(t.slaStatus ?? 'none')) {
        return false;
      }
      if (filter.sources.isNotEmpty && !filter.sources.contains(t.source)) {
        return false;
      }
      // Filed within the window. `createdAt` is nullable on the replica (a row
      // pulled before the column existed), and a null is EXCLUDED rather than
      // kept: a date filter that quietly keeps undated rows answers a
      // different question than the one asked.
      if (filter.from != null &&
          (t.createdAt == null || t.createdAt!.isBefore(filter.from!))) {
        return false;
      }
      if (filter.to != null &&
          (t.createdAt == null || t.createdAt!.isAfter(filter.to!))) {
        return false;
      }
      switch (filter.assigneeScope) {
        case TicketAssigneeScope.any:
          break;
        case TicketAssigneeScope.unassigned:
          if ((assignees[t.id] ?? const []).isNotEmpty) return false;
        case TicketAssigneeScope.mine:
          if (me == null) return false;
          if (!(assignees[t.id] ?? const []).any((a) => a.userId == me)) {
            return false;
          }
        case TicketAssigneeScope.person:
          if (!(assignees[t.id] ?? const []).any(
            (a) => a.userId == filter.assigneeId,
          )) {
            return false;
          }
      }
      if (searching && (rank == null || !rank.containsKey(t.id))) return false;
      return true;
    }).toList();
    if (rank != null) {
      // Search order IS the answer's order: tier first, then whatever the
      // query ranked. Re-sorting by date afterwards would throw away the only
      // thing that made a result relevant.
      kept.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
      return kept;
    }
    // Finished work sinks. Within each half the newest is first, which the
    // query already decided — a stable sort keeps that.
    kept.sort((a, b) {
      final aDone = a.terminalAt != null ? 1 : 0;
      final bDone = b.terminalAt != null ? 1 : 0;
      return aDone.compareTo(bDone);
    });
    return kept;
  });
});

/// EE-169. What the queue is being searched for; empty = search off.
///
/// The same one-notifier-per-screen shape the other search surfaces use, so
/// leaving the queue leaves nothing filtered behind it.
final ticketSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Ranked ids for the current query, or null when search is off.
///
/// Offline by construction: it reads the replica's fold shadows, so the desk
/// searches on a factory floor with no signal. That is also what makes the
/// ARCHIVE invisible here — finished requests are swept off the device
/// (EE-091), so the empty state has to say so rather than let "no results"
/// mean "no such request" (ADR-0016 D16.3).
final ticketSearchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>?>((ref) async {
      final query = ref.watch(ticketSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return null;
      // Rebuild when the queue does: a request pulled in while the field is
      // open should appear, and a search that froze at its first run would be
      // a list that disagrees with the one behind it.
      ref.watch(ticketQueueProvider);
      return ref
          .watch(searchServiceProvider)
          .searchTickets(workspace.id, query);
    });

/// One ticket, watched: a status change pushed from another device redraws the
/// open detail rather than leaving a stale header on screen.
final ticketProvider = StreamProvider.family<TicketRecord?, String>((
  ref,
  ticketId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.tickets,
  )..where((t) => t.id.equals(ticketId))).watchSingleOrNull();
});

/// EE-258 — a colleague's name by their user id, from every roster this
/// device syncs.
///
/// A requester is usually NOT in the unit that answers them, so the request's
/// own workspace roster misses them. The team's general workspace — every
/// member is in it, and every member's device syncs it — does not. One map
/// for the whole screen, read with `select` per row, so a queue does not
/// open a stream per request.
final eeMemberNamesProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.memberProfiles).watch().map((rows) {
    final names = <String, String>{};
    for (final row in rows) {
      final name = row.displayName;
      if (name != null && name.isNotEmpty) {
        names.putIfAbsent(row.userId, () => name);
      }
    }
    return names;
  });
});

/// EE-258 — hands an address to the device's mail app. A provider so a test
/// can see which address a tap asked for, without a platform to open.
final eeMailLauncherProvider = Provider<Future<void> Function(String address)>(
  (ref) => (address) async {
    await launchUrl(Uri(scheme: 'mailto', path: address));
  },
);

/// The thread, oldest first — how a conversation is read.
final ticketCommentsProvider =
    StreamProvider.family<List<TicketCommentRecord>, String>((ref, ticketId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.ticketComments)
            ..where((c) => c.ticketId.equals(ticketId))
            ..orderBy([(c) => OrderingTerm(expression: c.createdAt)]))
          .watch();
    });

/// Which services this workspace's queue actually mentions.
///
/// Derived from the tickets on the device rather than fetched from the
/// catalogue endpoint: the filter should offer what is IN this queue, and the
/// catalogue is admin-gated (`services.manage`) so an ordinary agent could not
/// read it anyway.
final queueServiceIdsProvider = Provider<List<String>>(
  (ref) => (ref.watch(ticketQueueProvider).value ?? const <TicketRecord>[])
      .map((t) => t.serviceId)
      .whereType<String>()
      .toSet()
      .toList(),
);

/// Everyone on ONE request — the detail's view (EE-224), and the ticket twin
/// of `taskAssigneesProvider`: one query, joined to the roster for a name and
/// a colour, and not tied to the workspace on screen (a request opened from a
/// link may live in another unit this device syncs).
final ticketAssigneesForProvider =
    StreamProvider.family<List<Assignee>, String>((ref, ticketId) {
      final db = ref.watch(databaseProvider);
      final assignments = db.select(db.ticketAssignments)
        ..where((a) => a.ticketId.equals(ticketId))
        ..orderBy([(a) => OrderingTerm.asc(a.assignedAt)]);
      return assignments
          .join([
            leftOuterJoin(
              db.memberProfiles,
              db.memberProfiles.userId.equalsExp(db.ticketAssignments.userId) &
                  db.memberProfiles.workspaceId.equalsExp(
                    db.ticketAssignments.workspaceId,
                  ),
            ),
          ])
          .watch()
          .map(
            (rows) => rows.map((row) {
              final a = row.readTable(db.ticketAssignments);
              final p = row.readTableOrNull(db.memberProfiles);
              return Assignee(
                assignmentId: a.id,
                userId: a.userId,
                displayName: p?.displayName,
                initials: p?.initials,
                colorRgb: p?.colorRgb,
              );
            }).toList(),
          );
    });

/// Who is on each request in this workspace (EE-086) — item 9's avatar row,
/// the ticket half.
///
/// The same shape as `workspaceAssigneesProvider`: ONE query for the whole
/// queue rather than one per card, and a `select` at the call site so a ticket
/// gaining an assignee does not rebuild every other row in the list.
///
/// It is also the entitlement gate by construction: on a build with no overlay
/// the table is simply empty, so every card draws nothing and no screen has to
/// ask whether the feature exists.
final ticketAssigneesProvider = StreamProvider<Map<String, List<Assignee>>>((
  ref,
) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const <String, List<Assignee>>{});
  final db = ref.watch(databaseProvider);
  final assignments = db.select(db.ticketAssignments)
    ..where((a) => a.workspaceId.equals(workspace.id))
    ..orderBy([(a) => OrderingTerm.asc(a.assignedAt)]);
  return assignments
      .join([
        // A MISS here is meaningful rather than exceptional: the roster only
        // carries people in this unit, and an assignment can outlive somebody's
        // membership by the length of one sweep. The avatar renders as a
        // neutral tombstone instead of vanishing.
        leftOuterJoin(
          db.memberProfiles,
          db.memberProfiles.userId.equalsExp(db.ticketAssignments.userId) &
              db.memberProfiles.workspaceId.equalsExp(
                db.ticketAssignments.workspaceId,
              ),
        ),
      ])
      .watch()
      .map((rows) {
        final out = <String, List<Assignee>>{};
        for (final row in rows) {
          final a = row.readTable(db.ticketAssignments);
          final p = row.readTableOrNull(db.memberProfiles);
          (out[a.ticketId] ??= []).add(
            Assignee(
              assignmentId: a.id,
              userId: a.userId,
              displayName: p?.displayName,
              initials: p?.initials,
              colorRgb: p?.colorRgb,
            ),
          );
        }
        return out;
      });
});
