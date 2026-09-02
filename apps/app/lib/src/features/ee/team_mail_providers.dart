import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/team_mail_api.dart';
import 'data/team_mail_models.dart';
import 'providers.dart';

/// Team mail state (OPH-290).
///
/// Every mutation re-reads the whole row rather than patching state — the
/// idiom EE-099 settled and OPH-287 repeated. The reason is the same one and
/// it is sharper here than it looks: the server derives `missingRequired` from
/// the finished row, so a patched copy would be a row whose "can this be
/// switched on" answer the client invented.
final eeTeamMailApiProvider = Provider<EeTeamMailApi>(
  (ref) => EeTeamMailApi(ref.watch(apiClientProvider)),
);

final eeTeamMailProvider =
    AsyncNotifierProvider<EeTeamMailController, EeTeamMail?>(
      EeTeamMailController.new,
    );

class EeTeamMailController extends AsyncNotifier<EeTeamMail?> {
  @override
  Future<EeTeamMail?> build() async {
    // `teams`, not a feature of its own: every EE install can send mail, and
    // an instance without teams has no screen to reach this from.
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeTeamMailApiProvider).read();
  }

  /// `password` omitted leaves the stored one; passing null clears it. The
  /// distinction is the API's and the screen's both, so it is not collapsed
  /// into an empty string here.
  Future<void> patch({
    String? host,
    int? port,
    bool? secure,
    Object? username = _absent,
    Object? password = _absent,
    String? fromAddress,
    Object? fromName = _absent,
    bool? enabled,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(eeTeamMailApiProvider)
          .save(
            host: host,
            port: port,
            secure: secure,
            username: username,
            password: password,
            fromAddress: fromAddress,
            fromName: fromName,
            enabled: enabled,
          );
      return ref.read(eeTeamMailApiProvider).read();
    });
  }

  /// Sends a probe. Re-reads afterwards because the attempt writes `status`
  /// and `lastVerifiedAt` — the screen would otherwise show yesterday's red
  /// mark next to a test that just succeeded.
  Future<EeTeamMailTestResult> test({String? password, String? to}) async {
    final result = await ref
        .read(eeTeamMailApiProvider)
        .test(password: password, to: to);
    ref.invalidateSelf();
    return result;
  }
}

const Object _absent = Object();
