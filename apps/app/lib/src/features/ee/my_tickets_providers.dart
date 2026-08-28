import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/my_tickets_api.dart';
import 'providers.dart';

/// "My requests" (EE-087) — the one EE list that is deliberately NOT replica
/// backed, and the provider says why so the next reader does not "fix" it.
final eeMyTicketsApiProvider = Provider<EeMyTicketsApi>(
  (ref) => EeMyTicketsApi(ref.watch(apiClientProvider)),
);

/// A FutureProvider rather than a notifier: there is nothing to mutate here.
/// A requester opens a request through the ticket form and reads the answer
/// here; this list only ever shows what the server last said.
final eeMyTicketsProvider = FutureProvider<List<EeMyTicket>?>((ref) async {
  // No entitlement → the endpoint does not exist; asking would be a 404 on
  // every app start (the house idiom: no entitlement, no capability).
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  return ref.watch(eeMyTicketsApiProvider).list();
});
