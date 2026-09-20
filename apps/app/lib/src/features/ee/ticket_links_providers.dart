import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      if (!ref.watch(eeFeatureProvider('teams')))
        return const EeTicketRelations();
      return ref.watch(eeTicketLinksApiProvider).read(ticketId);
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
