// The whole surface, not a `show` list: the join predicate below uses
// drift's `&` on Expression<bool>, which is an extension the narrowed import
// does not carry.
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class TicketFilter {
  const TicketFilter({
    this.statuses = const {},
    this.priorities = const {},
    this.serviceId,
  });

  /// Empty means "no filter", NOT "nothing" — the distinction the screen's
  /// chips rely on, and the one an `isEmpty` check gets wrong in the other
  /// direction if the default were "all statuses selected".
  final Set<String> statuses;
  final Set<String> priorities;
  final String? serviceId;

  bool get isEmpty =>
      statuses.isEmpty && priorities.isEmpty && serviceId == null;

  TicketFilter copyWith({
    Set<String>? statuses,
    Set<String>? priorities,
    String? serviceId,
    bool clearService = false,
  }) => TicketFilter(
    statuses: statuses ?? this.statuses,
    priorities: priorities ?? this.priorities,
    serviceId: clearService ? null : (serviceId ?? this.serviceId),
  );
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
      return true;
    }).toList();
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
