import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart';
import '../../calendar/apple/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/caldav_api.dart';
import '../providers.dart';
import 'caldav_connect_sheet.dart';

/// Settings → iCloud or CalDAV calendar (OPH-380, ADR-0059): the server-side
/// mirror for people whose calendar lives in iCloud but who are on the web,
/// Android, Windows or Linux — and for any CalDAV server (Nextcloud,
/// Radicale…).
///
/// Shown only where it applies: hidden while the server admin has not turned
/// the connector on (`CALDAV_ENABLED`) and nothing is connected. An existing
/// connection stays visible everywhere, so it can always be disconnected.
class CaldavCalendarCard extends ConsumerStatefulWidget {
  const CaldavCalendarCard({super.key});

  @override
  ConsumerState<CaldavCalendarCard> createState() => _CaldavCalendarCardState();
}

class _CaldavCalendarCardState extends ConsumerState<CaldavCalendarCard> {
  AppLifecycleListener? _lifecycle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(caldavIntegrationProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// The first sync starts on the server the moment a calendar is chosen;
  /// pull right away so the user's own events show up while they look.
  void _pullSoon() {
    final engine = ref.read(syncEngineProvider);
    if (engine != null) unawaited(engine.syncNow());
  }

  bool get _onAppleDevice => ref.read(appleCalendarGatewayProvider).isSupported;

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

  String _message(ApiException e) => switch (e.code) {
    'CALENDAR_ACCOUNT_REAUTH_REQUIRED' => 'calendar.caldav.reauth'.tr(),
    'CALDAV_NOT_ENABLED' => 'calendar.caldav.notEnabled'.tr(),
    'CALDAV_UNREACHABLE' => 'calendar.caldav.unreachable'.tr(),
    'NETWORK_ERROR' => 'calendar.networkError'.tr(),
    _ => e.message,
  };

  Future<void> _connect(String workspaceId, {CaldavAccount? reconnect}) async {
    final result = await showCaldavConnectSheet(
      context,
      workspaceId: workspaceId,
      offerIcloud: !_onAppleDevice,
      reconnect: reconnect,
    );
    if (result == null || !mounted) return;
    ref.invalidate(caldavIntegrationProvider);
    _pullSoon();
    // Several calendars and none chosen yet: nothing mirrors until one is —
    // so the choice comes right away, not as a hidden second step.
    if (result.account.calendarUrl == null && result.calendars.isNotEmpty) {
      await _pickCalendar(result.account, initial: result.calendars);
    }
  }

  Future<void> _pickCalendar(
    CaldavAccount account, {
    List<CaldavCalendar>? initial,
  }) async {
    final chosen = await showModalBottomSheet<CaldavCalendar>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _CaldavCalendarPicker(accountId: account.id, initial: initial),
    );
    if (chosen == null) return;
    await _guard(() async {
      await ref
          .read(caldavIntegrationsApiProvider)
          .chooseCalendar(account.id, chosen.url);
      ref.invalidate(caldavIntegrationProvider);
      _pullSoon();
    });
  }

  /// Disconnect says what survives, and — for iCloud — what we CANNOT do:
  /// revoke the app-specific password (CALDAV.md §3.6). That half is theirs.
  Future<void> _confirmDisconnect(CaldavAccount account) async {
    final ok = await awConfirmDelete(
      context,
      title: 'calendar.disconnectConfirmTitle'.tr(),
      body: account.isIcloud
          ? 'calendar.caldav.disconnectBodyIcloud'.tr()
          : 'calendar.caldav.disconnectBodyGeneric'.tr(),
      confirmLabel: 'calendar.disconnect'.tr(),
    );
    if (!ok) return;
    await _guard(() async {
      await ref.read(caldavIntegrationsApiProvider).disconnect(account.id);
      ref.invalidate(caldavIntegrationProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final status = ref.watch(caldavIntegrationProvider).value;
    // Optional, and off by default: while loading, on an error (an older
    // server without these routes) or with the connector off and nothing
    // connected, there is nothing to offer.
    if (workspace == null || status == null) return const SizedBox.shrink();
    final account = status.account;
    if (!status.enabled && account == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Card(
        key: const Key('caldav-card'),
        child: account == null
            ? _disconnected(workspace.id)
            : _connected(workspace.id, account, enabled: status.enabled),
      ),
    );
  }

  Widget _disconnected(String workspaceId) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const Icon(Icons.cloud_sync_outlined),
        title: Text('calendar.caldav.title'.tr()),
        subtitle: Text(
          _onAppleDevice
              ? 'calendar.caldav.blurbAppleDevice'.tr()
              : 'calendar.caldav.blurb'.tr(),
        ),
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
            key: const Key('caldav-connect'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _busy ? null : () => _connect(workspaceId),
            icon: const Icon(Icons.link),
            label: Text('calendar.connect'.tr()),
          ),
        ),
      ),
    ],
  );

  Widget _connected(
    String workspaceId,
    CaldavAccount account, {
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            Icons.cloud_done_outlined,
            color: account.needsReconnect
                ? scheme.error
                : (account.needsCalendar || !enabled
                      ? tokens.warning
                      : tokens.success),
          ),
          title: Text(
            account.isIcloud
                ? 'calendar.caldav.icloud'.tr()
                : 'calendar.caldav.generic'.tr(),
          ),
          subtitle: Text('${account.username} · ${account.serverHost}'),
          trailing: IconButton(
            key: const Key('caldav-refresh'),
            tooltip: 'calendar.refresh'.tr(),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(caldavIntegrationProvider),
          ),
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x3,
            ),
            child: Text(
              'calendar.caldav.serverOff'.tr(),
              key: const Key('caldav-server-off'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else if (account.needsReconnect) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x2,
            ),
            child: AwInlineError(
              key: const Key('caldav-reauth'),
              message: account.isIcloud
                  ? 'calendar.caldav.passwordRejectedIcloud'.tr()
                  : 'calendar.caldav.passwordRejected'.tr(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x3,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('caldav-reconnect'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busy
                    ? null
                    : () => _connect(workspaceId, reconnect: account),
                icon: const Icon(Icons.key_outlined),
                label: Text('calendar.caldav.reconnect'.tr()),
              ),
            ),
          ),
        ] else
          ListTile(
            key: const Key('caldav-calendar-row'),
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text('calendar.calendar'.tr()),
            subtitle: Text(
              account.calendarName ??
                  account.calendarUrl ??
                  'calendar.chooseWhich'.tr(),
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
          key: const Key('caldav-disconnect'),
          leading: Icon(Icons.link_off, color: scheme.error),
          title: Text(
            'calendar.disconnect'.tr(),
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            account.isIcloud
                ? 'calendar.caldav.disconnectSubIcloud'.tr()
                : 'calendar.disconnectSub'.tr(),
          ),
          onTap: _busy ? null : () => _confirmDisconnect(account),
        ),
      ],
    );
  }
}

class _CaldavCalendarPicker extends ConsumerWidget {
  const _CaldavCalendarPicker({required this.accountId, this.initial});

  final String accountId;

  /// Calendars the connect call already listed — no second round-trip.
  final List<CaldavCalendar>? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = initial != null
        ? AsyncValue.data(initial!)
        : ref.watch(caldavCalendarsProvider(accountId));
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
                  ? 'calendar.caldav.reauth'.tr()
                  : 'calendar.couldNotLoad'.tr(),
              onRetry: () => ref.invalidate(caldavCalendarsProvider(accountId)),
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
                  key: Key('caldav-calendar-${calendar.url}'),
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(calendar.name),
                  onTap: () => Navigator.of(context).pop(calendar),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
