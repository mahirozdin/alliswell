import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/team_webhooks_api.dart';
import 'data/team_webhooks_models.dart';
import 'providers.dart';

/// Outgoing endpoint providers (EE-176).
///
/// Every mutation re-reads the whole area rather than patching state — the
/// idiom EE-099 settled, and here it earns its keep twice: an endpoint's
/// `updatedAt` and its four secret characters both change on the server, and a
/// controller that patched one field would leave a row describing a world that
/// no longer exists.
final eeTeamWebhooksApiProvider = Provider<EeTeamWebhooksApi>(
  (ref) => EeTeamWebhooksApi(ref.watch(apiClientProvider)),
);

final eeTeamWebhooksProvider =
    AsyncNotifierProvider<EeTeamWebhooksController, EeWebhooksData?>(
      EeTeamWebhooksController.new,
    );

class EeTeamWebhooksController extends AsyncNotifier<EeWebhooksData?> {
  @override
  Future<EeWebhooksData?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeTeamWebhooksApiProvider).load();
  }

  /// Returns the secret, which exists in the clear for this one moment. The
  /// caller is responsible for putting it in front of somebody — nothing
  /// stores it, here or anywhere else.
  Future<String?> create({
    required String url,
    required List<String> eventClasses,
  }) async {
    final api = ref.read(eeTeamWebhooksApiProvider);
    final minted = await api.create(url: url, eventClasses: eventClasses);
    await _reload();
    return minted.secret;
  }

  Future<String?> rotateSecret(String id) async {
    final api = ref.read(eeTeamWebhooksApiProvider);
    final minted = await api.update(id, rotateSecret: true);
    await _reload();
    return minted.secret;
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    await ref.read(eeTeamWebhooksApiProvider).update(id, enabled: enabled);
    await _reload();
  }

  Future<void> setEvents(String id, List<String> eventClasses) async {
    await ref
        .read(eeTeamWebhooksApiProvider)
        .update(id, eventClasses: eventClasses);
    await _reload();
  }

  Future<void> remove(String id) async {
    await ref.read(eeTeamWebhooksApiProvider).remove(id);
    await _reload();
  }

  /// Queues a real delivery and returns its id so the screen can point at the
  /// row rather than claim success it has not seen.
  Future<String?> sendTest(String id) =>
      ref.read(eeTeamWebhooksApiProvider).sendTest(id);

  Future<void> _reload() async {
    state = await AsyncValue.guard(
      () => ref.read(eeTeamWebhooksApiProvider).load(),
    );
  }
}

/// The recent attempts at one endpoint. A family rather than a field on the
/// list: a screen that is not looking at an endpoint should not be paying for
/// its history.
final eeWebhookDeliveriesProvider =
    FutureProvider.family<List<EeWebhookDelivery>, String>((ref, id) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      return ref.watch(eeTeamWebhooksApiProvider).deliveries(id);
    });
