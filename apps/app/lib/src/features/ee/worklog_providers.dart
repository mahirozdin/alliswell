import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/worklog_api.dart';
import 'data/worklog_models.dart';
import 'providers.dart';

/// EE-208's panel (one request's hours).
///
/// `FutureProvider.family` + `ref.invalidate`, which is the house idiom and is
/// written down one file over: "this repo has no `FamilyAsyncNotifier`, and
/// reaching for one cost two rounds in Faz 2" (`assets_providers.dart`). It
/// cost a round here too — the rule was already in the codebase and this file
/// was written before reading it.
final eeWorklogApiProvider = Provider<EeWorklogApi>(
  (ref) => EeWorklogApi(ref.watch(apiClientProvider)),
);

/// Null means "not yours" or "no team here" — not an error to be shown, and
/// not an empty panel either: a screen has to be able to tell "you cannot see
/// this" apart from "nobody has logged anything".
final eeWorklogProvider = FutureProvider.family<EeWorklogPanel?, String>((
  ref,
  ticketId,
) async {
  // No entitlement → the endpoint does not exist; asking would be a 404 on
  // every open (the house idiom: no entitlement, no capability).
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  return ref.watch(eeWorklogApiProvider).load(ticketId);
});

/// The two mutations, as plain functions beside the provider they invalidate.
///
/// They re-read rather than patching the list in place, and the TOTALS are the
/// reason: those are the server's arithmetic, and a client that adjusted them
/// locally would be the one place a cross-currency sum could appear.
///
/// There is no `edit`. A correction is a withdrawal and a new entry, so a
/// month's total cannot change after the month was reported with the ledger
/// saying only that something was updated.
class EeWorklogActions {
  const EeWorklogActions(this._ref, this.ticketId);

  final Ref _ref;
  final String ticketId;

  /// MY hours. There is deliberately no `userId` parameter: entering a
  /// colleague's time needs `tickets.manage_worklog` and belongs on a
  /// supervisor's surface, not on the field technician's one-tap path.
  Future<void> add({
    required int minutes,
    String? workedOn,
    String? note,
  }) async {
    await _ref
        .read(eeWorklogApiProvider)
        .add(ticketId, minutes: minutes, workedOn: workedOn, note: note);
    _ref.invalidate(eeWorklogProvider(ticketId));
  }

  Future<void> remove(String worklogId) async {
    await _ref.read(eeWorklogApiProvider).remove(ticketId, worklogId);
    _ref.invalidate(eeWorklogProvider(ticketId));
  }
}

final eeWorklogActionsProvider = Provider.family<EeWorklogActions, String>(
  (ref, ticketId) => EeWorklogActions(ref, ticketId),
);
