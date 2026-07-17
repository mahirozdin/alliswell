import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/google_api.dart';
import '../providers.dart';

/// Settings → Google Calendar (OPH-080). The server side has been complete
/// since OPH-070…076; this is the only way a user can reach it.
///
/// The flow is deliberately small: connect → pick a calendar → done. Consent
/// happens in a real browser (the callback is a server-rendered page), so when
/// the app comes back it simply re-reads the status.
class GoogleCalendarCard extends ConsumerStatefulWidget {
  const GoogleCalendarCard({super.key});

  @override
  ConsumerState<GoogleCalendarCard> createState() => _GoogleCalendarCardState();
}

class _GoogleCalendarCardState extends ConsumerState<GoogleCalendarCard> {
  AppLifecycleListener? _lifecycle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Consent finishes in another app/tab, so the only signal that anything
    // happened is coming back. (Web lifecycle is unreliable — the explicit
    // refresh action below is the guarantee, this is the courtesy.)
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(googleIntegrationProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Server codes → something a person can act on (no jargon in end-user UI).
  String _message(ApiException e) => switch (e.code) {
    'GOOGLE_NOT_CONFIGURED' => 'calendar.notSetUpYet'.tr(),
    'CALENDAR_ACCOUNT_REAUTH_REQUIRED' => 'calendar.reauthLong'.tr(),
    'NETWORK_ERROR' => 'calendar.networkError'.tr(),
    _ => e.message,
  };

  Future<void> _connect(String workspaceId) => _guard(() async {
    final url = await ref
        .read(googleIntegrationsApiProvider)
        .connectUrl(workspaceId);
    await ref.read(urlLauncherProvider)(Uri.parse(url));
  });

  Future<void> _disconnect(GoogleAccount account) => _guard(() async {
    await ref.read(googleIntegrationsApiProvider).disconnect(account.id);
    ref.invalidate(googleIntegrationProvider);
  });

  Future<void> _pickCalendar(GoogleAccount account) async {
    final chosen = await showModalBottomSheet<GoogleCalendar>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CalendarPicker(accountId: account.id),
    );
    if (chosen == null) return;
    await _guard(() async {
      await ref
          .read(googleIntegrationsApiProvider)
          .chooseCalendar(account.id, chosen.id);
      ref.invalidate(googleIntegrationProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final status = ref.watch(googleIntegrationProvider);

    return Card(
      child: status.when(
        loading: () => ListTile(
          leading: const Icon(Icons.event_outlined),
          title: Text('calendar.calendar'.tr()),
          subtitle: Text('calendar.checking'.tr()),
        ),
        error: (_, _) =>
            AwInlineError(message: 'calendar.couldNotCheckGoogle'.tr()),
        data: (data) {
          if (workspace == null || data == null) return const SizedBox.shrink();
          // Optional integration: a server without an OAuth client is not
          // broken. Say so plainly — self-hosters are usually their own admin
          // and this is the hint that tells them what to set up.
          if (!data.configured) {
            return ListTile(
              key: const Key('google-not-configured'),
              leading: const Icon(Icons.event_outlined),
              title: Text('calendar.calendar'.tr()),
              subtitle: Text('calendar.notSetUpServer'.tr()),
            );
          }
          final account = data.account;
          return account == null
              ? _disconnected(workspace.id)
              : _connected(account);
        },
      ),
    );
  }

  Widget _disconnected(String workspaceId) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text('calendar.google'.tr()),
        subtitle: Text('calendar.googleBlurb'.tr()),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('google-connect'),
            onPressed: _busy ? null : () => _connect(workspaceId),
            icon: const Icon(Icons.link),
            label: Text('calendar.connect'.tr()),
          ),
        ),
      ),
    ],
  );

  Widget _connected(GoogleAccount account) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            Icons.event_available_outlined,
            // Green only once it is actually working — a connected account
            // with no calendar mirrors nothing.
            color: account.needsReconnect
                ? scheme.error
                : (account.needsCalendar ? tokens.warning : tokens.success),
          ),
          title: Text('calendar.google'.tr()),
          subtitle: Text(account.providerAccountId),
          trailing: IconButton(
            key: const Key('google-refresh'),
            tooltip: 'calendar.refresh'.tr(),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(googleIntegrationProvider),
          ),
        ),
        if (account.needsReconnect)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x3,
            ),
            child: AwInlineError(
              key: const Key('google-reauth'),
              message: 'calendar.googleSignedOut'.tr(),
            ),
          )
        else
          ListTile(
            key: const Key('google-calendar-row'),
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text('calendar.calendar'.tr()),
            subtitle: Text(
              account.defaultCalendarId ?? 'calendar.chooseWhich'.tr(),
              style: TextStyle(
                color: account.needsCalendar
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
                fontWeight: account.needsCalendar ? null : FontWeight.w600,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            onTap: _busy ? null : () => _pickCalendar(account),
          ),
        const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
        ListTile(
          key: const Key('google-disconnect'),
          leading: Icon(Icons.link_off, color: scheme.error),
          title: Text(
            'calendar.disconnect'.tr(),
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
          ),
          subtitle: Text('calendar.disconnectSub'.tr()),
          onTap: _busy ? null : () => _disconnect(account),
        ),
      ],
    );
  }
}

class _CalendarPicker extends ConsumerWidget {
  const _CalendarPicker({required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(googleCalendarsProvider(accountId));
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: calendars.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AwSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AwSpace.x4),
            child: AwErrorState(
              message:
                  e is ApiException &&
                      e.code == 'CALENDAR_ACCOUNT_REAUTH_REQUIRED'
                  ? 'calendar.reauthShort'.tr()
                  : 'calendar.couldNotLoad'.tr(),
              onRetry: () => ref.invalidate(googleCalendarsProvider(accountId)),
            ),
          ),
          data: (items) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AwSpace.x4),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x4,
                  0,
                  AwSpace.x4,
                  AwSpace.x2,
                ),
                child: Text(
                  'calendar.chooseTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final calendar in items)
                ListTile(
                  key: Key('calendar-${calendar.id}'),
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(calendar.summary),
                  subtitle: calendar.primary
                      ? Text('calendar.default'.tr())
                      : null,
                  onTap: () => Navigator.of(context).pop(calendar),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
