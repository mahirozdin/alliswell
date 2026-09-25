import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/unit_tickets_api.dart';
import 'providers.dart';

/// EE-267 (AW-E19) — "Birimlerim": open requests across every unit this
/// person works in, and the SLA alerts among them.
///
/// Both reads are the server's and wait for the reachability signal
/// (OPH-342): when the app already knows it is offline they do not ask, and
/// the screen says the list needs a connection. That is D17.9's rule made
/// mechanical — an old copy shown as if it were current is exactly what this
/// feature exists not to do, so there is no old copy to show.
final eeUnitTicketsApiProvider = Provider<EeUnitTicketsApi>(
  (ref) => EeUnitTicketsApi(ref.watch(apiClientProvider)),
);

const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer", as opposed to an answer.
bool unitTicketsNeedConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// Which page of the list: alerts only or all, and where it starts (`''` for
/// the first page, then each page's `nextCursor`) — so the screen stacks
/// pages without a notifier to hold them, as the archive does.
typedef EeUnitTicketsKey = ({bool alertsOnly, String cursor});

final eeUnitTicketsPageProvider = FutureProvider.autoDispose
    .family<EeUnitTicketsPage, EeUnitTicketsKey>((ref, key) async {
      // No entitlement → the endpoint does not exist (the house idiom).
      if (!ref.watch(eeFeatureProvider('teams'))) {
        return const EeUnitTicketsPage();
      }
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      return ref
          .watch(eeUnitTicketsApiProvider)
          .list(
            alertsOnly: key.alertsOnly,
            cursor: key.cursor.isEmpty ? null : key.cursor,
          );
    });

/// The current unit's last pull — the queue's own heartbeat. The strip asks
/// again on each beat, so it is exactly as live as the queue under it (a
/// pull a minute, sooner when the socket nudges) with no timer of its own.
final eeCurrentUnitPulledAtProvider = StreamProvider.autoDispose<DateTime?>((
  ref,
) {
  final here = ref.watch(currentWorkspaceProvider.select((w) => w.value?.id));
  if (here == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncStates)..where((s) => s.workspaceId.equals(here)))
      .watchSingleOrNull()
      .map((row) => row?.lastPulledAt)
      .distinct();
});

/// The queue's strip: SLA alerts in this person's OTHER units — the unit on
/// screen has its own queue — the most urgent three, and the counts.
///
/// Quiet on every failure: the strip is a doorway, not a screen, and "Birimlerim"
/// is where the connection state is said out loud.
final eeOtherUnitsAlertsProvider =
    FutureProvider.autoDispose<EeUnitTicketsPage>((ref) async {
      if (!ref.watch(eeFeatureProvider('teams'))) {
        return const EeUnitTicketsPage();
      }
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        return const EeUnitTicketsPage();
      }
      final here = ref.watch(
        currentWorkspaceProvider.select((w) => w.value?.id),
      );
      if (here == null) return const EeUnitTicketsPage();
      // Asked again on every pull of the unit on screen. Until the heartbeat
      // has said anything the strip waits, so opening the queue asks once.
      final beat = ref.watch(eeCurrentUnitPulledAtProvider);
      if (beat.isLoading) return const EeUnitTicketsPage();
      try {
        return await ref
            .watch(eeUnitTicketsApiProvider)
            .list(alertsOnly: true, except: here, limit: 3);
      } on ApiException {
        return const EeUnitTicketsPage();
      }
    });
