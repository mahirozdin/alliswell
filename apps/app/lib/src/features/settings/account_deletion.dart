import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';

/// Account deletion from inside the app — required by both stores (App Store
/// guideline 5.1.1(v), Google Play's account-deletion policy) and, more to the
/// point, the only honest way to offer an account.
///
/// The server schedules rather than erases: it answers with the instant the
/// deletion becomes irreversible, and signing back in before then can cancel
/// it. The UI's job is to make both the request and the way out of it obvious.
class AccountDeletionState {
  const AccountDeletionState({this.scheduledAt, required this.graceDays});

  /// When the account is erased for good. Null = no deletion pending.
  final DateTime? scheduledAt;
  final int graceDays;

  bool get isPending => scheduledAt != null;
}

class AccountDeletionApi {
  const AccountDeletionApi(this._ref);

  final Ref _ref;

  /// Current state, read from `GET /me`. Throws on network/auth failure so the
  /// caller can show a real error instead of implying "nothing scheduled".
  Future<AccountDeletionState> load() async {
    final res = await _ref.read(apiClientProvider).get('/api/v1/me');
    final user = (res.data as Map)['user'] as Map;
    return AccountDeletionState(
      scheduledAt: _parse(user['deletionScheduledAt']),
      // Only the deletion endpoints report the window; assume the documented
      // default until one of them tells us otherwise.
      graceDays: 3,
    );
  }

  Future<AccountDeletionState> requestDeletion() async {
    final res = await _ref.read(apiClientProvider).delete('/api/v1/me');
    final data = res.data as Map;
    return AccountDeletionState(
      scheduledAt: _parse(data['deletionScheduledAt']),
      graceDays: (data['graceDays'] as num?)?.toInt() ?? 3,
    );
  }

  Future<AccountDeletionState> cancelDeletion() async {
    final res = await _ref
        .read(apiClientProvider)
        .post('/api/v1/me/deletion/cancel');
    final data = res.data as Map;
    return AccountDeletionState(
      scheduledAt: _parse(data['deletionScheduledAt']),
      graceDays: (data['graceDays'] as num?)?.toInt() ?? 3,
    );
  }

  static DateTime? _parse(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}

final accountDeletionApiProvider = Provider<AccountDeletionApi>(
  AccountDeletionApi.new,
);

/// The pending-deletion state for the Settings screen. Invalidate after a
/// request or a cancel so the row re-renders from the server's answer rather
/// than a local guess.
final accountDeletionProvider =
    FutureProvider.autoDispose<AccountDeletionState>(
      (ref) => ref.watch(accountDeletionApiProvider).load(),
    );
