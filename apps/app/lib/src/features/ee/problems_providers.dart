import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../../search/providers.dart';
import '../../search/search.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/problems_api.dart';
import 'data/problems_models.dart';
import 'providers.dart';
import 'ticket_links_providers.dart';

/// Problem management on the phone (EE-270, AW-E09's problem half).
///
/// The change screens' split (EE-269), for the record that needs it most: a
/// problem is the desk's shared understanding of a fault, and its WORKAROUND
/// is the sentence an agent reads to somebody on the phone — often from a
/// factory floor with no signal. So the whole record opens from the device's
/// copy; the server is asked only for what the copy cannot carry (the
/// requests the problem explains, whose link lives on the request's side) and
/// for a record this device does not hold. Nothing asked is kept between
/// openings.
final eeProblemsApiProvider = Provider<EeProblemsApi>(
  (ref) => EeProblemsApi(ref.watch(apiClientProvider)),
);

/// The display order of the server's statuses: what an agent can act on
/// first. A grouping of the word the server sent, not a map of what may
/// follow it — moving a problem stays the server's (§0.0/6).
const List<String> kProblemStatusOrder = [
  'known_error',
  'investigating',
  'resolved',
  'closed',
];

/// The list, grouped by status in [kProblemStatusOrder], newest change first
/// inside a group. A status the app has no word for yet sorts last rather
/// than disappearing.
List<EeProblem> orderProblems(Iterable<EeProblem> rows) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  int rank(String status) {
    final i = kProblemStatusOrder.indexOf(status);
    return i < 0 ? kProblemStatusOrder.length : i;
  }

  return [...rows]..sort((a, b) {
    final byStatus = rank(a.status) - rank(b.status);
    if (byStatus != 0) return byStatus;
    final byTime = (b.updatedAt ?? b.createdAt ?? epoch).compareTo(
      a.updatedAt ?? a.createdAt ?? epoch,
    );
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
}

/// EE-270 — the list, from the replica of the current workspace. No
/// entitlement gate, for the queue's reason (see `eeChangeListProvider`).
final eeProblemListProvider = StreamProvider.autoDispose<List<EeProblem>>((
  ref,
) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return Stream.value(const <EeProblem>[]);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.problems,
  )..where((p) => p.workspaceId.equals(workspace.id))).watch().map(
    (rows) => orderProblems([for (final r in rows) EeProblem.fromRecord(r)]),
  );
});

/// One problem from the device's copy, by id — whichever workspace holds it.
final eeProblemOnDeviceProvider = StreamProvider.autoDispose
    .family<EeProblem?, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.problems)..where((p) => p.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : EeProblem.fromRecord(row));
    });

const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer".
bool problemNeedsConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// EE-270 — what the detail reads from the server, every time and in one go.
///
/// Offline it fails without asking (OPH-342); without the entitlement it asks
/// nothing and answers null.
final eeProblemLiveProvider = FutureProvider.autoDispose
    .family<EeProblemLive?, String>((ref, id) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return null;
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      final api = ref.watch(eeProblemsApiProvider);
      final (problem, tickets) = await (api.get(id), api.tickets(id)).wait;
      return EeProblemLive(problem: problem, tickets: tickets);
    });

/// EE-270 — the problem list's search field. `searchProblems` has been ready
/// since EE-188 with no caller, and `check:search-reachable` carried an
/// exemption saying so until this screen (OPH-348 makes that exemption fail
/// the moment a caller exists).
final problemSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

final problemSearchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>?>((ref) async {
      final query = ref.watch(problemSearchQueryProvider).trim();
      if (query.isEmpty) return null;
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return null;
      return ref
          .watch(searchServiceProvider)
          .searchProblems(workspace.id, query);
    });

/// The one write the problem screens make: raising a record.
final eeProblemActionsProvider = Provider<EeProblemActions>(
  EeProblemActions.new,
);

class EeProblemActions {
  EeProblemActions(this._ref);
  final Ref _ref;

  /// From a request, the request decides the desk and is linked in the same
  /// step (EE-280) — so its detail is read again to show the record; from
  /// the list, the desk on screen.
  Future<EeProblem> create({
    required String title,
    required String symptom,
    String? workaround,
    EeProblemSource? source,
  }) async {
    final workspace = _ref.read(currentWorkspaceProvider).value;
    final problem = await _ref
        .read(eeProblemsApiProvider)
        .create(
          title: title,
          symptom: symptom,
          workaround: workaround,
          sourceTicketId: source?.ticketId,
          workspaceId: source == null ? workspace?.id : null,
        );
    if (source != null) {
      _ref.invalidate(eeTicketRelationsProvider(source.ticketId));
    }
    unawaited(_ref.read(syncEngineProvider)?.syncNow());
    return problem;
  }
}
