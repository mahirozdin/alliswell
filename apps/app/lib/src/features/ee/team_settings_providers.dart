import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../files/providers.dart';
import 'data/team_settings.dart';
import 'data/team_settings_api.dart';

/// Team settings providers (EE-037). Server-only `AsyncValue` — the api_keys
/// pattern — because settings are tenant-wide state, not a per-replica row:
/// there is nothing here for the sync protocol to carry, and an admin
/// editing them is inherently online.

final eeTeamSettingsApiProvider = Provider<EeTeamSettingsApi>(
  (ref) => EeTeamSettingsApi(ref.watch(apiClientProvider)),
);

final eeTeamSettingsProvider =
    AsyncNotifierProvider<EeTeamSettingsController, EeTeamSettings>(
      EeTeamSettingsController.new,
    );

class EeTeamSettingsController extends AsyncNotifier<EeTeamSettings> {
  @override
  Future<EeTeamSettings> build() => ref.watch(eeTeamSettingsApiProvider).read();

  /// Saves the fields the form actually touched. The server answers with the
  /// stored truth (normalized colour, trimmed name), and THAT is what the
  /// screen shows next — never the text the user typed.
  Future<void> save({
    String? name,
    String? locale,
    String? timezone,
    String? colorRgb,
    Set<String> clear = const {},
  }) async {
    final api = ref.read(eeTeamSettingsApiProvider);
    state = await AsyncValue.guard(
      () => api.update(
        name: name,
        locale: locale,
        timezone: timezone,
        colorRgb: colorRgb,
        clear: clear,
      ),
    );
  }

  /// The three-step logo upload, from the app's side: ask for a destination,
  /// PUT the bytes straight to storage over the shared transport, then ask
  /// the server to adopt the object it can now verify.
  ///
  /// A failure at step 2 leaves nothing behind but an unreferenced object —
  /// the row still points at the previous logo, so a broken upload never
  /// blanks a team's identity.
  Future<void> uploadLogo(PickedUpload picked) async {
    final api = ref.read(eeTeamSettingsApiProvider);
    state = await AsyncValue.guard(() async {
      final ticket = await api.startLogoUpload(
        contentType: picked.mime ?? 'image/png',
        sizeBytes: picked.sizeBytes,
      );
      await ref.read(uploadTransportProvider)(
        url: ticket.url,
        headers: ticket.headers,
        source: picked,
      );
      return api.completeLogo(key: ticket.key, sizeBytes: picked.sizeBytes);
    });
  }

  Future<void> removeLogo() async {
    final api = ref.read(eeTeamSettingsApiProvider);
    state = await AsyncValue.guard(api.removeLogo);
  }
}
