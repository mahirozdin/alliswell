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

/// The mailboxes this desk reads (EE-180).
///
/// Its own provider rather than a field on the relay's row: they share a
/// screen and a permission, and nothing else. A single object would make
/// every inbox edit re-read the relay's settings and every relay edit
/// re-read the inboxes.
final eeMailInboxesProvider =
    AsyncNotifierProvider<EeMailInboxesController, List<EeMailInbox>>(
      EeMailInboxesController.new,
    );

class EeMailInboxesController extends AsyncNotifier<List<EeMailInbox>> {
  @override
  Future<List<EeMailInbox>> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return const [];
    return ref.watch(eeTeamMailApiProvider).inboxes();
  }

  Future<void> save({
    String? id,
    String? name,
    String? host,
    int? port,
    bool? secure,
    String? username,
    String? password,
    String? folder,
    String? serviceId,
    bool? enabled,
  }) async {
    await ref
        .read(eeTeamMailApiProvider)
        .saveInbox(
          id: id,
          name: name,
          host: host,
          port: port,
          secure: secure,
          username: username,
          password: password,
          folder: folder,
          serviceId: serviceId,
          enabled: enabled,
        );
    await _reload();
  }

  Future<void> remove(String id) async {
    await ref.read(eeTeamMailApiProvider).removeInbox(id);
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(
      () => ref.read(eeTeamMailApiProvider).inboxes(),
    );
  }
}
