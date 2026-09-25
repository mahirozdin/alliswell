import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../auth/providers.dart';
import 'data/absences_api.dart';
import 'providers.dart';

/// EE-236 (AW-E18) — absences and the on-call cover they cause.
///
/// Both reads are the server's and wait for the reachability signal
/// (OPH-342): when the app already knows it is offline they do not ask at
/// all, and the screen says the list needs a connection instead of drawing
/// an empty one that reads as "nobody is away".
final eeAbsencesApiProvider = Provider<EeAbsencesApi>(
  (ref) => EeAbsencesApi(ref.watch(apiClientProvider)),
);

const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer", as opposed to an answer.
bool absencesNeedConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// Today and the next three months: mine, my unit colleagues', or the
/// whole team's for somebody who records them for others.
final eeAbsencePageProvider = FutureProvider.autoDispose<EeAbsencePage>((
  ref,
) async {
  // No entitlement → the endpoint does not exist (the house idiom).
  if (!ref.watch(eeFeatureProvider('teams'))) return const EeAbsencePage();
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    throw _unreachable;
  }
  return ref.watch(eeAbsencesApiProvider).list();
});

/// Who is on call in each unit this person is in — and whom they cover for.
final eeMyOnCallProvider = FutureProvider.autoDispose<List<EeOnCallNow>>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const [];
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    throw _unreachable;
  }
  return ref.watch(eeAbsencesApiProvider).onCallMine();
});
