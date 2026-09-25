import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../../search/providers.dart';
import '../../search/search.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'approvals_providers.dart';
import 'data/changes_api.dart';
import 'data/changes_models.dart';
import 'providers.dart';

/// Change management on the phone (EE-269, AW-E09).
///
/// ── THE DEVICE'S COPY FOR THE PLAN, THE SERVER FOR THE REST ────────────
///
/// EE-186 has sent every change to the devices of its desk since it landed,
/// "for the factory floor with no signal: what is going out tonight, when its
/// window is, and whether anybody signed for it" — and until EE-269 nothing
/// read that copy. The split now:
///
///   the list      the replica of the CURRENT workspace (the queue's rule:
///                 the engine syncs one workspace at a time)
///   the plan      the replica, by id — title, type, risk, window, impact,
///                 the way back — readable with no signal
///   the rest      the server, asked every time the detail opens: who was
///                 asked to sign and what they said, what the window meets in
///                 the calendar, which services and machines it touches, and
///                 the request it came from
///
/// The second half is never kept between openings. A signature given a
/// minute ago drawn as still pending, or a freeze declared this morning
/// missing from a calendar read last week, would be old data passing for
/// current — EE-238's rule, and the reason [eeChangeLiveProvider] is
/// autoDispose.
final eeChangesApiProvider = Provider<EeChangesApi>(
  (ref) => EeChangesApi(ref.watch(apiClientProvider)),
);

/// The list, split by TIME rather than by status.
///
/// A status split would need to know which statuses end which type's life —
/// the server's type-keyed map — and a copy of it here would be the second
/// state machine §0.0/6 forbids. The clock needs no map: a window is ahead, it
/// is not set yet, or it is over. Each row still says its status in the
/// server's word.
class EeChangeList {
  const EeChangeList({
    this.ahead = const [],
    this.unscheduled = const [],
    this.past = const [],
  });

  /// Window not over yet (including one open right now), soonest first.
  final List<EeChange> ahead;

  /// No window yet — still being written, or abandoned before it had one.
  /// Newest first.
  final List<EeChange> unscheduled;

  /// Window over, most recent first.
  final List<EeChange> past;

  bool get isEmpty => ahead.isEmpty && unscheduled.isEmpty && past.isEmpty;
  List<EeChange> get all => [...ahead, ...unscheduled, ...past];
}

EeChangeList splitChanges(Iterable<EeChange> rows, {required DateTime now}) {
  final ahead = <EeChange>[];
  final unscheduled = <EeChange>[];
  final past = <EeChange>[];
  for (final change in rows) {
    if (!change.hasWindow) {
      unscheduled.add(change);
    } else if (change.windowEnd!.isAfter(now)) {
      ahead.add(change);
    } else {
      past.add(change);
    }
  }
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  ahead.sort((a, b) => a.windowStart!.compareTo(b.windowStart!));
  unscheduled.sort(
    (a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch),
  );
  past.sort((a, b) => b.windowStart!.compareTo(a.windowStart!));
  return EeChangeList(ahead: ahead, unscheduled: unscheduled, past: past);
}

/// EE-269 — the list, from the replica of the current workspace.
///
/// No entitlement gate, for the queue's reason (`assets_providers.dart`): the
/// replica holds only what the server sent, and a gate answering "no" while
/// the entitlement check is still loading would draw an empty list in exactly
/// the place this exists for.
final eeChangeListProvider = StreamProvider.autoDispose<EeChangeList>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const EeChangeList());
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.changes,
  )..where((c) => c.workspaceId.equals(workspace.id))).watch().map(
    (rows) => splitChanges([
      for (final row in rows) EeChange.fromRecord(row),
    ], now: DateTime.now()),
  );
});

/// One change from the device's copy, by id — whichever workspace holds it.
/// `null` means this device does not hold it; the detail then draws the
/// server's copy.
final eeChangeOnDeviceProvider = StreamProvider.autoDispose
    .family<EeChange?, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.changes)..where((c) => c.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : EeChange.fromRecord(row));
    });

/// "The server could not be reached", in the shape every surface here
/// already draws (`asApiException`'s network error).
const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer", as opposed to an answer.
bool changeNeedsConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// EE-269 — everything the detail reads from the server, asked every time it
/// opens and in one go: the server's copy (services, source request), the
/// signatures, the machines, and what the window meets in the calendar.
///
/// Offline it fails as [_unreachable] WITHOUT asking — the app already knows
/// (OPH-342), and a request bound to fail would only repeat it after a
/// timeout. Without the entitlement the endpoints do not exist, so nothing is
/// asked and the answer is null.
final eeChangeLiveProvider = FutureProvider.autoDispose
    .family<EeChangeLive?, String>((ref, id) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return null;
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      final api = ref.watch(eeChangesApiProvider);
      final change = await api.get(id);
      final (approvals, assets, conflicts) = await (
        api.approvals(id),
        api.assets(id),
        api.conflicts(change),
      ).wait;
      return EeChangeLive(
        change: change,
        approvals: approvals,
        assets: assets,
        conflicts: change.hasWindow ? conflicts : null,
      );
    });

/// EE-279 — the changes raised from one request, for the request's detail.
///
/// Quiet when it cannot answer (offline, or no entitlement): the section is an
/// addition to a detail that already works, like the relations it sits with.
final eeChangesRaisedFromProvider = FutureProvider.autoDispose
    .family<List<EeChange>, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        return const [];
      }
      return ref.watch(eeChangesApiProvider).raisedFrom(ticketId);
    });

/// EE-269 — the change list's search field. `searchChanges` has been ready
/// since EE-186 and had no caller: by OPH-326's rule the entity did not exist
/// for anybody searching, and `check:search-reachable` carried an exemption
/// saying so until this screen.
final changeSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Ranked ids, or null when search is off (the house contract: EMPTY means
/// "open and nothing matched", which gets its own empty state).
final changeSearchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>?>((ref) async {
      final query = ref.watch(changeSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return null;
      return ref
          .watch(searchServiceProvider)
          .searchChanges(workspace.id, query);
    });

/// The two writes the change screens make — both through doors that already
/// exist, and both followed by a pull so the device's copy catches up.
final eeChangeActionsProvider = Provider<EeChangeActions>(EeChangeActions.new);

class EeChangeActions {
  EeChangeActions(this._ref);
  final Ref _ref;

  /// Raises one. From a request, the request decides the desk (EE-279);
  /// otherwise the desk on screen does.
  Future<EeChange> create({
    required String title,
    required String type,
    required String risk,
    required String impact,
    required String rollbackPlan,
    String? description,
    DateTime? windowStart,
    DateTime? windowEnd,
    List<String> serviceIds = const [],
    EeChangeSource? source,
  }) async {
    final workspace = _ref.read(currentWorkspaceProvider).value;
    final change = await _ref
        .read(eeChangesApiProvider)
        .create(
          title: title,
          type: type,
          risk: risk,
          impact: impact,
          rollbackPlan: rollbackPlan,
          description: description,
          windowStart: windowStart,
          windowEnd: windowEnd,
          serviceIds: serviceIds,
          sourceTicketId: source?.ticketId,
          workspaceId: source == null ? workspace?.id : null,
        );
    if (source != null) {
      _ref.invalidate(eeChangesRaisedFromProvider(source.ticketId));
    }
    unawaited(_ref.read(syncEngineProvider)?.syncNow());
    return change;
  }

  /// Signs (or refuses) one — EE-184's decision door, the one the approvals
  /// screen uses. The change's detail and the approver's queue are both read
  /// again: each describes a world that just moved.
  Future<void> decide({
    required String changeId,
    required String approvalId,
    required bool approve,
    required String reason,
  }) async {
    await _ref
        .read(eeApprovalsApiProvider)
        .decide(approvalId, approve: approve, reason: reason);
    _ref.invalidate(eeChangeLiveProvider(changeId));
    _ref.invalidate(eeApprovalsProvider);
    unawaited(_ref.read(syncEngineProvider)?.syncNow());
  }
}
