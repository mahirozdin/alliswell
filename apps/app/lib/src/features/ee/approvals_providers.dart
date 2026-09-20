import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/approvals_api.dart';
import 'data/approvals_models.dart';
import 'providers.dart';

/// Approval providers (EE-184).
///
/// A decision re-reads the whole list rather than patching the row out of it —
/// EE-099's idiom, and it earns its keep here: deciding one approval can
/// change ANOTHER row's meaning (the second signature on the same request is
/// now the only thing holding it), and a controller that removed one item
/// would leave the rest describing a world that had moved on.
final eeApprovalsApiProvider = Provider<EeApprovalsApi>(
  (ref) => EeApprovalsApi(ref.watch(apiClientProvider)),
);

final eeApprovalsProvider =
    AsyncNotifierProvider<EeApprovalsController, List<EeApproval>>(
      EeApprovalsController.new,
    );

class EeApprovalsController extends AsyncNotifier<List<EeApproval>> {
  bool _mine = true;
  String _status = 'pending';

  /// Whose queue is on screen. The screen reads it back so its toggle cannot
  /// disagree with what was actually fetched.
  bool get mine => _mine;
  String get status => _status;

  @override
  Future<List<EeApproval>> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return const [];
    return ref.watch(eeApprovalsApiProvider).list(status: _status, mine: _mine);
  }

  Future<void> setScope({required bool mine}) async {
    if (_mine == mine) return;
    _mine = mine;
    await _reload();
  }

  Future<void> setStatus(String status) async {
    if (_status == status) return;
    _status = status;
    await _reload();
  }

  /// Answers one, then re-reads. The reason is required here as well as on the
  /// server: a client that let it through empty would turn a 400 into the
  /// user's problem at the end of a form they already filled in.
  Future<void> decide(
    String id, {
    required bool approve,
    required String reason,
  }) async {
    await ref
        .read(eeApprovalsApiProvider)
        .decide(id, approve: approve, reason: reason);
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(
      () => ref.read(eeApprovalsApiProvider).list(status: _status, mine: _mine),
    );
  }
}
