import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/team_ai_api.dart';
import 'data/team_ai_models.dart';
import 'providers.dart';

/// Team AI credential providers (EE-111).
///
/// Every mutation re-reads the whole area rather than patching state — the
/// idiom EE-099 settled — and here the reason is the policy: it arrives in the
/// same response as the list, and storing a key for a team whose members are
/// forbidden their own changes what the screen must say about BOTH halves. A
/// controller that patched one field would leave the other explaining a world
/// that no longer exists.
final eeTeamAiApiProvider = Provider<EeTeamAiApi>(
  (ref) => EeTeamAiApi(ref.watch(apiClientProvider)),
);

final eeTeamAiProvider =
    AsyncNotifierProvider<EeTeamAiController, EeTeamAiData?>(
      EeTeamAiController.new,
    );

class EeTeamAiController extends AsyncNotifier<EeTeamAiData?> {
  @override
  Future<EeTeamAiData?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeTeamAiApiProvider).load();
  }

  Future<void> save({
    required String provider,
    String? apiKey,
    String? baseUrl,
    String? chatModel,
    String? fastModel,
  }) => _then(
    (api) => api.save(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      chatModel: chatModel,
      fastModel: fastModel,
    ),
  );

  Future<void> remove(String id) => _then((api) => api.remove(id));

  Future<void> setPersonalKeysAllowed(bool allowed) =>
      _then((api) => api.setPersonalKeysAllowed(allowed));

  Future<void> _then(Future<void> Function(EeTeamAiApi api) action) async {
    state = await AsyncValue.guard(() async {
      final api = ref.read(eeTeamAiApiProvider);
      await action(api);
      return api.load();
    });
  }
}
