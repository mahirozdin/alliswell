import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/units_api.dart';
import 'data/units_models.dart';
import 'providers.dart';

/// Unit providers (EE-057).
///
/// The interesting one is [eeUnitsProvider], and what makes it interesting is
/// what it does NOT do: it never asks `canProvider('units.manage_members')`.
///
/// That gate answers from the cached grants of the caller's ROLE, and a
/// delegated unit manager is an ordinary `member` everywhere else — their
/// authority comes from a unit row the server evaluates per unit, not from
/// their role. Gating this screen on the role cache would hide the feature
/// from exactly the people it was built for, quietly, and only in production
/// where somebody actually holds a delegation.
///
/// So the LIST endpoint is the gate. Null means "you may act on no unit";
/// an empty list means "you may, there just are none yet" — an admin opening
/// their first unit lives in that second case, and the two must not collapse.

final eeUnitsApiProvider = Provider<EeUnitsApi>(
  (ref) => EeUnitsApi(ref.watch(apiClientProvider)),
);

final eeUnitsProvider = AsyncNotifierProvider<EeUnitsController, List<EeUnit>?>(
  EeUnitsController.new,
);

class EeUnitsController extends AsyncNotifier<List<EeUnit>?> {
  @override
  Future<List<EeUnit>?> build() async {
    // No entitlement → the endpoints do not exist; asking would be a 404 on
    // every app start (the house idiom: no entitlement, no capability).
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    try {
      return await ref.watch(eeUnitsApiProvider).list();
    } catch (_) {
      // Offline, or no team here. Either way there is no unit surface to draw.
      return null;
    }
  }

  /// Every mutation re-reads the list rather than patching it: the server may
  /// have refused, renamed around a collision, or changed what this caller is
  /// allowed to see next. One request, and it cannot disagree with the server.
  Future<void> _then(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return ref.read(eeUnitsApiProvider).list();
    });
  }

  Future<void> create(String name) =>
      _then(() => ref.read(eeUnitsApiProvider).create(name));

  Future<void> rename(String unitId, String name) =>
      _then(() => ref.read(eeUnitsApiProvider).rename(unitId, name));

  Future<void> setArchived(String unitId, {required bool archived}) => _then(
    () => ref.read(eeUnitsApiProvider).setArchived(unitId, archived: archived),
  );
}

/// Should a "Units" entry exist at all?
///
/// True for a team admin (even with zero units — that is where the first one
/// is opened) and for a delegated manager (who has at least one). False while
/// loading, unlike [canProvider]: this decides whether a NAVIGATION ROW
/// appears, and a row that flickers in and out on every launch is worse than
/// one that arrives a moment late.
final eeUnitsVisibleProvider = Provider<bool>(
  (ref) => ref.watch(eeUnitsProvider).value != null,
);

/// One unit's people. A family, because two units are two questions.
///
/// A plain [FutureProvider] rather than a notifier: every mutation here is a
/// server call followed by a re-read, and [EeUnitMemberActions] does exactly
/// that — a notifier would add a state machine around a value that is only
/// ever "whatever the server last said".
final eeUnitMembersProvider = FutureProvider.family<List<EeUnitMember>, String>(
  (ref, unitId) => ref.watch(eeUnitsApiProvider).members(unitId),
);

/// Who could still join. Fetched only when a picker opens — a family so the
/// answer belongs to the unit it was asked about.
final eeUnitCandidatesProvider =
    FutureProvider.family<List<EeUnitMember>, String>(
      (ref, unitId) => ref.watch(eeUnitsApiProvider).candidates(unitId),
    );

/// The mutations on one unit's roster.
///
/// Each one re-reads BOTH lists. The unit list carries a member count, so it
/// goes stale the moment this roster changes; refreshing only what is on
/// screen would leave the number on the screen behind it wrong.
class EeUnitMemberActions {
  const EeUnitMemberActions(this._ref, this.unitId);
  final Ref _ref;
  final String unitId;

  Future<void> add(String userId) =>
      _after(() => _ref.read(eeUnitsApiProvider).addMember(unitId, userId));

  Future<void> remove(String userId) =>
      _after(() => _ref.read(eeUnitsApiProvider).removeMember(unitId, userId));

  Future<void> setRole(String userId, String role) => _after(
    () => _ref.read(eeUnitsApiProvider).setMemberRole(unitId, userId, role),
  );

  Future<void> _after(Future<void> Function() action) async {
    await action();
    _ref.invalidate(eeUnitMembersProvider(unitId));
    _ref.invalidate(eeUnitCandidatesProvider(unitId));
    _ref.invalidate(eeUnitsProvider);
  }
}

final eeUnitMemberActionsProvider =
    Provider.family<EeUnitMemberActions, String>(
      (ref, unitId) => EeUnitMemberActions(ref, unitId),
    );
