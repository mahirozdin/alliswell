import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import 'apple_calendar_gateway.dart';
import 'providers.dart';

/// Settings → Apple Calendar (OPH-078). The device-side twin of the Google card
/// (OPH-080): request access, pick which calendar to mirror INTO, show status.
/// Renders nothing off Apple platforms — there is no EventKit there.
///
/// Apple has no server, so this feature lives entirely on the device: turning
/// it on here is what makes `calendarMirrorEnabled` tasks appear in the local
/// Calendar app.
class AppleCalendarCard extends ConsumerWidget {
  const AppleCalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Not an Apple device → the whole feature is absent, no empty card.
    if (!ref.watch(appleCalendarGatewayProvider).isSupported) {
      return const SizedBox.shrink();
    }
    final access = ref.watch(appleAccessProvider);
    return Card(
      child: access.when(
        loading: () => ListTile(
          leading: const Icon(Icons.event_outlined),
          title: Text('calendar.apple'.tr()),
          subtitle: Text('calendar.checking'.tr()),
        ),
        error: (_, _) =>
            AwInlineError(message: 'calendar.couldNotCheckApple'.tr()),
        data: (status) => _body(context, ref, status),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, EventKitAccess status) {
    switch (status) {
      case EventKitAccess.fullAccess:
        return _Connected();
      case EventKitAccess.denied:
      case EventKitAccess.restricted:
        // A dead end the app cannot argue with — only the user, in iOS/macOS
        // Settings. Say exactly that instead of a useless retry button.
        return ListTile(
          key: const Key('apple-blocked'),
          leading: const Icon(Icons.event_busy_outlined),
          title: Text('calendar.apple'.tr()),
          subtitle: Text('calendar.appleBlocked'.tr()),
        );
      case EventKitAccess.writeOnly:
      case EventKitAccess.notDetermined:
        return _Disconnected(
          // writeOnly can create but not read, which breaks re-linking — treat
          // it like "not connected" and ask again for full access.
          note: status == EventKitAccess.writeOnly
              ? 'calendar.appleFullAccess'.tr()
              : 'calendar.appleBlurb'.tr(),
        );
    }
  }
}

class _Disconnected extends ConsumerStatefulWidget {
  const _Disconnected({required this.note});

  final String note;

  @override
  ConsumerState<_Disconnected> createState() => _DisconnectedState();
}

class _DisconnectedState extends ConsumerState<_Disconnected> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await ref.read(appleCalendarGatewayProvider).requestAccess();
    } finally {
      // Re-read the (possibly changed) status either way.
      ref.invalidate(appleAccessProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text('calendar.apple'.tr()),
        subtitle: Text(widget.note),
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
            key: const Key('apple-connect'),
            onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.link),
            label: Text('calendar.connect'.tr()),
          ),
        ),
      ),
    ],
  );
}

class _Connected extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.awTokens;
    final chosen = ref.watch(appleCalendarIdProvider);
    final hasCalendar = chosen.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            Icons.event_available_outlined,
            // Green only once a calendar is chosen — access alone mirrors
            // nothing (same honesty as the Google card).
            color: hasCalendar ? tokens.success : tokens.warning,
          ),
          title: Text('calendar.apple'.tr()),
          subtitle: Text(
            hasCalendar
                ? 'calendar.connected'.tr()
                : 'calendar.accessGranted'.tr(),
          ),
        ),
        ListTile(
          key: const Key('apple-calendar-row'),
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text('calendar.calendar'.tr()),
          subtitle: Text(
            hasCalendar ? chosen : 'calendar.chooseWhich'.tr(),
            style: TextStyle(
              color: hasCalendar ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: hasCalendar ? FontWeight.w600 : null,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          onTap: () => _pick(context, ref),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CalendarPicker(),
    );
    if (chosen != null) {
      await ref.read(appleCalendarIdProvider.notifier).set(chosen);
    }
  }
}

class _CalendarPicker extends ConsumerWidget {
  const _CalendarPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(_appleCalendarsProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: calendars.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AwSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(AwSpace.x4),
            child: AwErrorState(
              message: 'calendar.couldNotLoad'.tr(),
              onRetry: () => ref.invalidate(_appleCalendarsProvider),
            ),
          ),
          data: (items) {
            // Only writable calendars can receive our events — a subscribed or
            // holiday calendar would fail every save, so it is not offered.
            final writable = items.where((c) => c.isWritable).toList();
            return ListView(
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
                  child: Text('calendar.chooseTitle'.tr()),
                ),
                for (final calendar in writable)
                  ListTile(
                    key: Key('apple-calendar-${calendar.id}'),
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(calendar.title),
                    subtitle: calendar.accountName != null
                        ? Text(calendar.accountName!)
                        : null,
                    onTap: () => Navigator.of(context).pop(calendar.id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fetched only while the picker is open — one EventKit round-trip.
final _appleCalendarsProvider = FutureProvider<List<AppleCalendar>>(
  (ref) => ref.watch(appleCalendarGatewayProvider).calendars(),
);
