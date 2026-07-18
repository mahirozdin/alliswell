import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';

/// Best-effort push of the chosen language to the account (OPH-126) so it can
/// follow the user to another device via `PATCH /api/v1/me`.
///
/// Device-local persistence (`AwI18n` → localKv) is the source of truth; this is
/// fire-and-forget: a no-op when signed out, and silent on failure (the local
/// choice already succeeded). Seeding the app FROM `users.locale` on a fresh
/// sign-in is a follow-up — the app has no `/me` fetch flow yet.
final accountLocaleSyncProvider = Provider<Future<void> Function(String)>((
  ref,
) {
  return (String languageCode) async {
    if (ref.read(authControllerProvider).value == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .patch('/api/v1/me', data: {'locale': languageCode});
    } catch (_) {
      // Best-effort: the device already persisted the choice.
    }
  };
});
