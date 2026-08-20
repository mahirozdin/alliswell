import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/team_admin_api.dart';
import 'data/team_admin_models.dart';
import 'providers.dart';

/// Team-admin providers (EE-042). Server-only `AsyncValue`s, deliberately
/// uncached: these answer "who may do what", and a stale answer to that is
/// worse than no answer. The sync roster (EE-017) is the cached one, and it
/// carries different data for a different purpose.

final eeTeamAdminApiProvider = Provider<EeTeamAdminApi>(
  (ref) => EeTeamAdminApi(ref.watch(apiClientProvider)),
);

/// The team this address serves, or null. Null is the ordinary answer on a
/// plain instance and on the apex — not an error, and not a reason to draw
/// anything.
final eeTeamProvider = FutureProvider<EeTeamInfo?>((ref) async {
  // No entitlement → the endpoints do not exist; asking would be a 404 on
  // every app start (the house idiom: no entitlement, no capability).
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  try {
    return await ref.watch(eeTeamAdminApiProvider).info();
  } catch (_) {
    // Offline, or not a member: either way there is no team surface to draw.
    return null;
  }
});

/// The one question the Settings index asks: should a "Team" group exist?
///
/// Both halves are required. The entitlement decides whether the capability
/// exists at all; the ROLE decides whether this person has anything to do
/// there. A member who sees an admin group and gets 403 behind it has been
/// told a small lie by their own app.
final eeTeamAdminProvider = Provider<bool>((ref) {
  final team = ref.watch(eeTeamProvider).value;
  return team != null && team.isAdmin;
});

final eeTeamRosterProvider =
    AsyncNotifierProvider<EeRosterController, EeTeamRoster>(
      EeRosterController.new,
    );

class EeRosterController extends AsyncNotifier<EeTeamRoster> {
  @override
  Future<EeTeamRoster> build() => ref.watch(eeTeamAdminApiProvider).members();

  /// Every mutation re-reads the roster rather than patching it in place: the
  /// server may have refused, adjusted a seat count, or changed what the
  /// caller is allowed to see next. Re-reading is one request and cannot
  /// disagree with the server.
  Future<void> _then(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return ref.read(eeTeamAdminApiProvider).members();
    });
  }

  Future<void> setRole(String userId, String role) => _then(
    () => ref.read(eeTeamAdminApiProvider).setRole(userId: userId, role: role),
  );

  Future<void> deactivate(String userId) =>
      _then(() => ref.read(eeTeamAdminApiProvider).deactivate(userId));

  Future<void> reactivate(String userId) =>
      _then(() => ref.read(eeTeamAdminApiProvider).reactivate(userId));

  Future<void> remove(String userId) =>
      _then(() => ref.read(eeTeamAdminApiProvider).remove(userId));
}

final eeInvitesProvider =
    AsyncNotifierProvider<EeInvitesController, List<EeInvite>>(
      EeInvitesController.new,
    );

class EeInvitesController extends AsyncNotifier<List<EeInvite>> {
  @override
  Future<List<EeInvite>> build() => ref.watch(eeTeamAdminApiProvider).invites();

  /// Returns what was minted so the screen can show it ONCE. It is not kept
  /// in provider state: a credential that survives a rebuild is a credential
  /// sitting in memory for no reason.
  Future<EeMintedInvite> mint({
    required String email,
    required String role,
  }) async {
    final minted = await ref
        .read(eeTeamAdminApiProvider)
        .invite(email: email, role: role);
    ref.invalidateSelf();
    return minted;
  }

  Future<void> revoke(String inviteId) async {
    state = await AsyncValue.guard(() async {
      await ref.read(eeTeamAdminApiProvider).revokeInvite(inviteId);
      return ref.read(eeTeamAdminApiProvider).invites();
    });
  }
}
