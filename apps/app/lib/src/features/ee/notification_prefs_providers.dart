import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/notification_prefs_api.dart';

/// Notification preference providers (EE-076/EE-077).
///
/// Server-only `AsyncValue` — the team-settings pattern — and deliberately NOT
/// a synced entity. A preference is answered where it is enforced: the server
/// reads it inside `notifyEvent` before anything is queued, so a replica's copy
/// could only ever be a second opinion that changes nothing. The screen is
/// inherently online for the same reason the roles screen is.
///
/// (The notification LIST is the opposite — it syncs, because reading it is
/// exactly what somebody does with no signal. Two halves of one feature, two
/// different answers, each with its own reason.)

final eeNotificationPrefsApiProvider = Provider<EeNotificationPrefsApi>(
  (ref) => EeNotificationPrefsApi(ref.watch(apiClientProvider)),
);

final eeNotificationPrefsProvider =
    AsyncNotifierProvider<EeNotificationPrefsController, EeNotificationPrefs>(
      EeNotificationPrefsController.new,
    );

class EeNotificationPrefsController extends AsyncNotifier<EeNotificationPrefs> {
  @override
  Future<EeNotificationPrefs> build() =>
      ref.watch(eeNotificationPrefsApiProvider).read();

  /// Flips one switch and sends the WHOLE matrix, because that is what the
  /// endpoint takes. The server answers with the stored truth and THAT is what
  /// the screen shows next — never the state the toggle optimistically
  /// assumed, which is how a locked switch would otherwise appear to move.
  Future<void> setMuted({
    required String eventClass,
    required String channel,
    required bool muted,
  }) async {
    final current = state.value;
    if (current == null) return;
    final pair = '$eventClass:$channel';
    final pairs = <String>{...current.mutedPairs};
    if (muted) {
      pairs.add(pair);
    } else {
      pairs.remove(pair);
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(eeNotificationPrefsApiProvider)
          .update(muted: pairs.toList(growable: false)),
    );
  }

  Future<void> setQuietHours({int? from, int? to}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(eeNotificationPrefsApiProvider)
          .update(
            quietFrom: from,
            quietTo: to,
            clearQuietHours: from == null || to == null,
          ),
    );
  }
}
