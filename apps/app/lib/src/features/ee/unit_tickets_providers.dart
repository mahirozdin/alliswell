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

/// R-11: the whole list (no alerts chip) is drawn newest first, the order a
/// unit's own queue reads in, while the server pages by lateness. So it asks
/// for the server's largest page, and follows the pages to the end before
/// it orders them ([eeAllOpenAcrossUnits], D-2), so the order the screen
/// gives covers all of them.
const int kEeAcrossUnitsFullPage = 100;

/// R-11: newest first — by the request number, the team's own filing order
/// (one sequence per team, so it orders across units too), and by the last
/// change where a row has no number yet. Stable: equal rows keep the
/// server's order.
List<EeUnitTicket> eeNewestFirst(Iterable<EeUnitTicket> rows) {
  final indexed = rows.toList().asMap().entries.toList();
  int byNewest(EeUnitTicket a, EeUnitTicket b) {
    final an = a.number;
    final bn = b.number;
    if (an != null && bn != null) return bn.compareTo(an);
    if (an != null) return -1;
    if (bn != null) return 1;
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    return 0;
  }

  indexed.sort((x, y) {
    final order = byNewest(x.value, y.value);
    return order != 0 ? order : x.key.compareTo(y.key);
  });
  return [for (final entry in indexed) entry.value];
}

final eeUnitTicketsPageProvider = FutureProvider.autoDispose
    .family<EeUnitTicketsPage, EeUnitTicketsKey>((ref, key) async {
      // No entitlement → the endpoint does not exist (the house idiom).
      if (!ref.watch(eeFeatureProvider('teams'))) {
        return const EeUnitTicketsPage();
      }
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      final api = ref.watch(eeUnitTicketsApiProvider);
      if (key.alertsOnly || key.cursor.isNotEmpty) {
        return api.list(
          alertsOnly: key.alertsOnly,
          cursor: key.cursor.isEmpty ? null : key.cursor,
          limit: key.alertsOnly ? null : kEeAcrossUnitsFullPage,
        );
      }
      return eeAllOpenAcrossUnits(api);
    });

/// D-2 (polish 3): how many of the server's pages the newest-first list
/// follows before it orders them — 20 × 100 open requests. Past it the
/// rest is a "show more" away, as before.
const int kEeAcrossUnitsMaxPages = 20;

/// D-2 (polish 3) — every open request across the person's units, for the
/// newest-first list.
///
/// The server pages by lateness (breached, warned, the rest by deadline)
/// and has no other order. R-11 ordered the first page newest first, so
/// past 100 open requests the newest ones — not late, deadlines far away —
/// sat on page 2 and the first screen was not the newest at all; "show
/// more" then dropped them in above what was read. The list now follows
/// the pages to the end (up to [kEeAcrossUnitsMaxPages]) and orders the
/// whole set once: the order a screen shows is the order of every row.
/// The head (units, counts, scope) is the first page's; [nextCursor] is
/// null unless the cap was reached.
Future<EeUnitTicketsPage> eeAllOpenAcrossUnits(EeUnitTicketsApi api) async {
  final first = await api.list(limit: kEeAcrossUnitsFullPage);
  final tickets = [...first.tickets];
  final seen = {for (final t in first.tickets) t.id};
  var next = first.nextCursor;
  final asked = <String>{};
  for (var page = 1; next != null && page < kEeAcrossUnitsMaxPages; page++) {
    // A cursor asked twice would be a loop, not a page.
    if (!asked.add(next)) {
      next = null;
      break;
    }
    final more = await api.list(cursor: next, limit: kEeAcrossUnitsFullPage);
    for (final t in more.tickets) {
      if (seen.add(t.id)) tickets.add(t);
    }
    next = more.nextCursor;
  }
  return EeUnitTicketsPage(
    units: first.units,
    tickets: tickets,
    breached: first.breached,
    warned: first.warned,
    unassigned: first.unassigned,
    scope: first.scope,
    nextCursor: next,
  );
}

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

/// HK-1 (polish 3) — Home's "your units" figures: open requests past their
/// SLA and due soon, across every unit the person works in (the same
/// `open_now` count the SLA board's "Open right now" and "My units" read).
///
/// Home stays mounted for the whole session, so a page read once at the
/// first visit kept its number while the sweep moved requests from "due
/// soon" to "past SLA": Home said 22 late while the board, opened later,
/// said 15 + 7 (and the other way round). This one asks again on every
/// pull of the unit on screen — exactly as live as the queue and the
/// other-units strip — and keeps its last answer while it asks.
final eeHomeOpenAlertsProvider = FutureProvider.autoDispose<EeUnitTicketsPage?>(
  (ref) async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
      return null;
    }
    // The heartbeat: a dependency only (its value is not needed), so each
    // pull asks again, and a heartbeat not yet known does not hold Home back.
    ref.watch(eeCurrentUnitPulledAtProvider);
    // One row is enough: the counts cover the whole scope, not the page.
    return ref.watch(eeUnitTicketsApiProvider).list(alertsOnly: true, limit: 1);
  },
);

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
