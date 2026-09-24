import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/requester_ticket_api.dart';

/// EE-252 — the requester's side of one request, read online (ADR-0011 §3:
/// the device never syncs a unit it is not a member of). Plain
/// `FutureProvider.family` + `ref.invalidate` after a write, the asset
/// screens' precedent.
final eeRequesterTicketApiProvider = Provider<EeRequesterTicketApi>(
  (ref) => EeRequesterTicketApi(ref.watch(apiClientProvider)),
);

final eeRequesterTicketProvider =
    FutureProvider.family<EeRequesterTicket?, String>(
      (ref, ticketId) =>
          ref.watch(eeRequesterTicketApiProvider).detail(ticketId),
    );

final eeRequesterCommentsProvider =
    FutureProvider.family<List<EeRequesterComment>, String>(
      (ref, ticketId) =>
          ref.watch(eeRequesterTicketApiProvider).comments(ticketId),
    );

/// EE-252 — the request's files this reader may see, read-only.
final eeRequesterFilesProvider =
    FutureProvider.family<List<EeTicketFile>, String>(
      (ref, ticketId) =>
          ref.watch(eeRequesterTicketApiProvider).files(ticketId),
    );
