import 'package:drift/drift.dart' show OrderingMode, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import 'data/ticket_links_api.dart';
import 'data/ticket_links_models.dart';
import 'providers.dart';

/// Links, linked work and the "came up again" flow (EE-189, EE-190).
///
/// This is the one part of the ticket detail that does NOT come from the
/// device's own copy, and the reason is the shape of the data: a link is a
/// claim ABOUT two records rather than a record, and its far end may be a
/// request this device never pulled. Replicating it would put rows on phones
/// that render as broken lines.
final eeTicketLinksApiProvider = Provider<EeTicketLinksApi>(
  (ref) => EeTicketLinksApi(ref.watch(apiClientProvider)),
);

/// Read as a whole, and re-read as a whole after every write — EE-099's
/// idiom. Opening a second piece of work changes what "the work this caused"
/// means, and patching one item into a cached list leaves the rest describing
/// a world that moved on. `ref.invalidate` is how a caller asks for that.
final eeTicketRelationsProvider =
    FutureProvider.family<EeTicketRelations, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) {
        return const EeTicketRelations();
      }
      return ref.watch(eeTicketLinksApiProvider).read(ticketId);
    });

/// EE-198 — which of a request's files came from OUTSIDE.
///
/// The ids come from the SERVER because provenance is the overlay's own fact
/// and core's file rows cannot carry it (core must not learn the overlay
/// exists). The files themselves come from the replica. The screen
/// intersects the two, which is why this returns ids and nothing else —
/// since EE-260, two sets of them ([EeExternalFiles]).
///
/// An empty answer is the safe default everywhere: a desk whose server has
/// not been updated sees its files without badges rather than an error, and
/// nothing is ever marked external by accident — only by being on this list.
final eeTicketExternalFilesProvider = FutureProvider.autoDispose
    .family<EeExternalFiles, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return EeExternalFiles.none;
      return ref.watch(eeTicketLinksApiProvider).externalFiles(ticketId);
    });

/// The titles of the work a request caused, read from the DEVICE's own copy.
///
/// The ids come from the server (they are a link, not a record) and the names
/// come from drift, because every task in the unit is already here and asking
/// the network for words the phone is holding would make this list blank on a
/// bad connection — which is the connection a shop floor has.
final eeLinkedTaskTitlesProvider =
    StreamProvider.family<Map<String, String>, List<String>>((ref, taskIds) {
      if (taskIds.isEmpty) return Stream.value(const <String, String>{});
      final db = ref.watch(databaseProvider);
      return (db.select(db.tasks)..where((t) => t.id.isIn(taskIds)))
          .watch()
          .map((rows) => {for (final row in rows) row.id: row.title});
    });

/// OPH-358 (UI-AUDIT #33) — the far end of a request's links, read from the
/// DEVICE: the number and subject of every request in this unit are already
/// here. A request this device does not hold (another unit's) is simply
/// absent from the map, and the row then says so rather than vanishing.
///
/// Keyed by the ids joined with commas: a list built during a build is a new
/// object every frame, and a family keyed by it would start over every frame.
final eeLinkedTicketsProvider =
    StreamProvider.family<Map<String, TicketRecord>, String>((ref, joined) {
      final ticketIds = [
        for (final id in joined.split(','))
          if (id.isNotEmpty) id,
      ];
      if (ticketIds.isEmpty) {
        return Stream.value(const <String, TicketRecord>{});
      }
      final db = ref.watch(databaseProvider);
      return (db.select(db.tickets)..where((t) => t.id.isIn(ticketIds)))
          .watch()
          .map((rows) => {for (final row in rows) row.id: row});
    });

/// The requests a link can point at: this unit's, newest first, from the
/// device. Capped — the picker filters as somebody types, and a desk looking
/// for "the other one" means a recent one.
final eeLinkCandidatesProvider =
    StreamProvider.family<List<TicketRecord>, String>((ref, workspaceId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.tickets)
            ..where((t) => t.workspaceId.equals(workspaceId))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(300))
          .watch();
    });

/// OPH-358 (UI-AUDIT #48) — the companies a request can be filed under.
final eeCustomerChoicesProvider =
    FutureProvider.autoDispose<List<EeCustomerChoice>>((ref) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      return ref.watch(eeTicketLinksApiProvider).customers();
    });
