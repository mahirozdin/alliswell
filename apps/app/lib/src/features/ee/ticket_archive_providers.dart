import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../auth/providers.dart';
import 'data/ticket_archive_api.dart';
import 'providers.dart';
import 'requester_ticket_providers.dart';

/// EE-266 (AW-E17) — the archive, readable (ADR-0017 D17.7).
///
/// EE-169 decided "no archive screen in the app": a finished request left the
/// device and the queue's empty search said "look in the archive on the
/// server" — an archive the app could not open. D17.7 turned that around once
/// EE-265 had stopped the archive losing what a request left behind. Every
/// read here is the server's and waits for the reachability signal (OPH-342):
/// offline, the screens say the archive needs a connection instead of
/// showing an empty list that reads as "no such request".
final eeTicketArchiveApiProvider = Provider<EeTicketArchiveApi>(
  (ref) => EeTicketArchiveApi(ref.watch(apiClientProvider)),
);

/// "The server could not be reached", in the shape a failed request becomes.
const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer", as opposed to an answer.
bool ticketNeedsConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// The archive's answer to a search — a number, or every word in the subject.
final eeArchiveSearchProvider = FutureProvider.autoDispose
    .family<EeArchivePage, String>((ref, query) async {
      final q = query.trim();
      if (q.isEmpty || !ref.watch(eeFeatureProvider('teams'))) {
        return const EeArchivePage();
      }
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      return ref.watch(eeTicketArchiveApiProvider).search(q);
    });

/// One archived request, or null when none this caller may read.
final eeArchivedTicketProvider = FutureProvider.autoDispose
    .family<EeArchivedTicket?, String>((ref, ticketId) async {
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      return ref.watch(eeTicketArchiveApiProvider).detail(ticketId);
    });

/// Where a request this device does not hold actually is.
///
/// Three answers that used to share one sentence ("closed, and dropped from
/// the device"), each of them wrong for two of the three cases — and the
/// asset card's history opened the live request of another unit into it:
sealed class EeTicketWhereabouts {
  const EeTicketWhereabouts();
}

/// The person reading is the one who ASKED (EE-252): their own view.
class EeTicketForRequester extends EeTicketWhereabouts {
  const EeTicketForRequester();
}

/// Live, and the desk's — in a unit of this person's that is not the one
/// open on the device (the engine syncs one workspace at a time).
class EeTicketInAnotherUnit extends EeTicketWhereabouts {
  const EeTicketInAnotherUnit(this.workspaceId);
  final String? workspaceId;
}

/// Finished and swept into the archive: readable, read-only.
class EeTicketArchived extends EeTicketWhereabouts {
  const EeTicketArchived(this.ticket);
  final EeArchivedTicket ticket;
}

/// Neither live nor archived for this person — "not yours" and "never was"
/// answer alike on the server, and do here.
class EeTicketNowhere extends EeTicketWhereabouts {
  const EeTicketNowhere();
}

/// EE-266 — asked when the device's replica misses: the live request first
/// (the same read EE-252's requester view makes, so it is made once), then
/// the archive.
final eeTicketWhereaboutsProvider = FutureProvider.autoDispose
    .family<EeTicketWhereabouts, String>((ref, ticketId) async {
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      final live = await ref.watch(eeRequesterTicketProvider(ticketId).future);
      if (live != null) {
        return live.isRequesterView
            ? const EeTicketForRequester()
            : EeTicketInAnotherUnit(live.workspaceId);
      }
      final archived = await ref
          .watch(eeTicketArchiveApiProvider)
          .detail(ticketId);
      return archived == null
          ? const EeTicketNowhere()
          : EeTicketArchived(archived);
    });
