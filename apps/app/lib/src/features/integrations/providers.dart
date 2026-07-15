import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/google_api.dart';

/// Opening the consent page. Behind a provider so widget tests can observe the
/// hand-off without a platform channel — and so the OAuth flow stays the only
/// thing this feature does to the outside world.
typedef UrlLauncher = Future<bool> Function(Uri url);

final urlLauncherProvider = Provider<UrlLauncher>(
  // externalApplication: consent must happen in a real browser the user can
  // inspect — never an in-app webview (Google blocks those anyway).
  (_) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

final googleIntegrationsApiProvider = Provider<GoogleIntegrationsApi>(
  (ref) => GoogleIntegrationsApi(ref.watch(apiClientProvider)),
);

/// Server state, so it is fetched — never cached in the replica (a stale
/// "connected" would be a lie). `ref.invalidate` it after every change and
/// when the app comes back from the consent browser.
final googleIntegrationProvider = FutureProvider<GoogleIntegrationStatus?>((
  ref,
) async {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  return ref.watch(googleIntegrationsApiProvider).status(workspace.id);
});

/// The calendars of a connected account — only fetched while the picker is
/// open, because it costs a round-trip to Google.
final googleCalendarsProvider =
    FutureProvider.family<List<GoogleCalendar>, String>(
      (ref, accountId) =>
          ref.watch(googleIntegrationsApiProvider).calendars(accountId),
    );
