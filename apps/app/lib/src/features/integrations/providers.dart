import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/persisted_prefs.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/caldav_api.dart';
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

// ── iCloud / CalDAV (OPH-380, ADR-0059) ─────────────────────────────────────

final caldavIntegrationsApiProvider = Provider<CaldavIntegrationsApi>(
  (ref) => CaldavIntegrationsApi(ref.watch(apiClientProvider)),
);

/// Whether the SERVER mirrors this workspace into an iCloud calendar, kept on
/// the device ('1' or ''). The Apple Calendar mirror on an iPhone or Mac reads
/// it: with both on, every task would appear twice in Apple Calendar. It is
/// persisted so an offline launch still honours it, and rewritten every time
/// the status loads.
final serverMirrorsIcloudProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('caldav_icloud_active', fallback: ''),
);

/// Server state, fetched — never cached in the replica. Invalidate after every
/// change and when the app comes back to the foreground.
final caldavIntegrationProvider = FutureProvider<CaldavStatus?>((ref) async {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return null;
  final status = await ref
      .watch(caldavIntegrationsApiProvider)
      .status(workspace.id);
  // Only while the server's connector is ON: an admin switching
  // CALDAV_ENABLED off stops the server mirror, and the device mirror must
  // then come back rather than leave Apple Calendar empty.
  final icloud =
      status.enabled &&
      status.accounts.any(
        (a) => a.isIcloud && a.status == 'active' && a.calendarUrl != null,
      );
  final flag = ref.read(serverMirrorsIcloudProvider.notifier);
  // Always written (not only when it differs): the stored value hydrates
  // asynchronously, so "differs" could be judged against the fallback. And
  // outside this provider's build — one provider may not write another while
  // it is being built.
  Future.microtask(() => flag.set(icloud ? '1' : ''));
  return status;
});

/// The calendars of a connected account — fetched only while the picker is
/// open (it costs a round-trip to the CalDAV server).
final caldavCalendarsProvider =
    FutureProvider.family<List<CaldavCalendar>, String>(
      (ref, accountId) =>
          ref.watch(caldavIntegrationsApiProvider).calendars(accountId),
    );
