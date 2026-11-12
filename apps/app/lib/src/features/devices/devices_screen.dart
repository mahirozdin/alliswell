import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_format.dart';
import '../../core/error_messages.dart';
import '../../core/tr_locative.dart';
import '../../i18n/i18n.dart';
import '../../sync/providers.dart' show syncClientIdProvider;
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/route_leading.dart';
import '../../widgets/status_views.dart';
import '../../widgets/word_safe_text.dart';
import '../auth/ui/sign_out.dart' show signOutWithConfirm;
import 'data/device_api.dart';
import 'device_detail_sheet.dart';
import 'device_display_name.dart';
import 'pick_alarm_device_page.dart';
import 'providers.dart';

/// A device not heard from for longer than this is folded under "Not seen
/// for a long time" (mobbin-alarm §2.3, R10): it is still listed, so nothing
/// is hidden, but it no longer pushes the live ones down.
const Duration kStaleDeviceAfter = Duration(days: 90);

/// The devices in the order the screen shows them.
///
/// [thisDevice] first; then the others, ringing ones before silent ones and
/// each group newest-seen first; anything unseen for [kStaleDeviceAfter] goes
/// to [stale] in the same order.
({DeviceInfo? thisDevice, List<DeviceInfo> others, List<DeviceInfo> stale})
arrangeDevices(List<DeviceInfo> devices, String? thisId, DateTime now) {
  DeviceInfo? self;
  final rest = <DeviceInfo>[];
  for (final device in devices) {
    if (thisId != null && device.id == thisId) {
      self = device;
    } else {
      rest.add(device);
    }
  }
  int seen(DeviceInfo a, DeviceInfo b) {
    final at = a.lastSeenAt, bt = b.lastSeenAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  rest.sort((a, b) {
    final ringA = a.ringsUrgent == true ? 0 : 1;
    final ringB = b.ringsUrgent == true ? 0 : 1;
    return ringA != ringB ? ringA - ringB : seen(a, b);
  });
  bool isStale(DeviceInfo d) {
    final at = d.lastSeenAt;
    return at != null && now.difference(at) > kStaleDeviceAfter;
  }

  return (
    thisDevice: self,
    others: [
      for (final d in rest)
        if (!isStale(d)) d,
    ],
    stale: [
      for (final d in rest)
        if (isStale(d)) d,
    ],
  );
}

/// The settings row's subtitle: where urgent alarms ring now.
String devicesSubtitle(DevicesView? view) {
  if (view == null || !view.supportsRingsUrgent) {
    return 'settings.devices.sub'.tr();
  }
  final ringing = view.ringing;
  return switch (ringing.length) {
    0 => 'settings.devices.subtitleNone'.tr(),
    1 => 'settings.devices.subtitleOne'.tr(
      args: {'device': deviceDisplayName(ringing.single)},
    ),
    final count => 'settings.devices.subtitleMany'.tr(
      args: {'count': '$count'},
    ),
  };
}

/// "Cihazlar" in Settings ▸ Notifications & alarms, with where urgent alarms
/// ring as its subtitle.
class DevicesSettingsRow extends ConsumerWidget {
  const DevicesSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: const Key('settings-devices'),
    leading: const Icon(Icons.devices_outlined),
    title: Text('settings.devices.title'.tr()),
    subtitle: Text(devicesSubtitle(ref.watch(devicesProvider).value)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push('/settings/devices'),
  );
}

/// Settings ▸ Devices (`/settings/devices`, #48, OPH-448): every device on the
/// account, which one this is, and per device whether urgent alarms ring
/// there. The switch is the server's setting (`PATCH
/// /api/v1/notification-devices/:id`); a device that does not ring gets the
/// same reminder as an ordinary notification.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key, this.signOut});

  /// "Sign out on this device" from the detail sheet; the app's own
  /// sign-out flow ([signOutWithConfirm]) unless a test hands in another.
  final Future<void> Function(BuildContext context, WidgetRef ref)? signOut;

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _staleOpen = false;

  @override
  void initState() {
    super.initState();
    // Home's card and band hold the list for the whole session (OPH-453), so
    // opening this screen would only show what Home read at launch (W-10).
    // A list already held is asked for again; a new one is being fetched.
    if (ref.exists(devicesProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(devicesProvider.notifier).refresh();
      });
    }
  }

  /// "Acil alarmlar hiçbir cihazda çalmayacak" — asked before the last
  /// ringing device goes off. A warning, never a block (Q7).
  Future<bool> _confirmLastOff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          key: const Key('devices-last-off-dialog'),
          title: Text('settings.devices.lastOffTitle'.tr()),
          content: Text('settings.devices.lastOffBody'.tr()),
          actions: [
            TextButton(
              key: const Key('devices-last-off-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('settings.devices.lastOffKeep'.tr()),
            ),
            // Destructive, so the error role (DESIGN §19 D5), never primary.
            FilledButton(
              key: const Key('devices-last-off-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('settings.devices.lastOffConfirm'.tr()),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _toggle(DeviceInfo device, bool value) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = deviceDisplayName(device);
    final controller = ref.read(devicesProvider.notifier);
    final view = ref.read(devicesProvider).value;
    // The list foresees it: ask first.
    final asked =
        !value &&
        device.ringsUrgent == true &&
        view != null &&
        view.ringing.length == 1;
    if (asked && !await _confirmLastOff()) return;
    if (!mounted) return;
    final result = await controller.setRingsUrgent(device.id, value);
    if (!mounted) return;
    if (result == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text('settings.devices.saveFailed'.tr())),
      );
      return;
    }
    // The server knew better than the list (another device changed in the
    // meantime): warn now, and "Cancel" puts this one back on.
    if (!value &&
        !asked &&
        result.warnings.contains('NO_URGENT_DEVICE') &&
        !await _confirmLastOff()) {
      if (!mounted) return;
      await controller.setRingsUrgent(device.id, true);
      return;
    }
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      (value ? 'settings.devices.announceOn' : 'settings.devices.announceOff')
          .tr(
            args: {
              'device': awAt(
                name,
                languageCode: AwI18n.instance.locale.languageCode,
              ),
            },
          ),
      Directionality.of(context),
    );
  }

  Future<void> _openDetails(DeviceInfo device, String? thisId) async {
    final view = ref.read(devicesProvider).value;
    final outcome = await showDeviceDetailSheet(
      context,
      device: device,
      isThis: device.id == thisId,
      offline: view?.offline ?? true,
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case DeviceSheetSignOut():
        await (widget.signOut ?? signOutWithConfirm)(context, ref);
      case DeviceSheetRemoved(:final removal):
        if (!removal.needsPick) return;
        await Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) =>
                PickAlarmDevicePage(devices: removal.devices, thisId: thisId),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final thisId = ref.watch(syncClientIdProvider.select((id) => id.value));
    final Widget body;
    if (devices.value case final view?) {
      body = _list(context, view, thisId);
    } else if (devices.hasError) {
      body = AwErrorState(
        message: localizedError(devices.error),
        onRetry: () => ref.invalidate(devicesProvider),
      );
    } else {
      body = ListView(
        key: const Key('devices-loading'),
        padding: awListPadding(context, top: AwSpace.x2),
        children: const [_SkeletonCard(), _SkeletonCard(), _SkeletonCard()],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('settings.devices.title'.tr()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: body,
        ),
      ),
    );
  }

  Widget _list(BuildContext context, DevicesView view, String? thisId) {
    final arranged = arrangeDevices(view.devices, thisId, DateTime.now());
    final supports = view.supportsRingsUrgent;
    final ringingCount = view.ringing.length;

    Widget card(DeviceInfo device) => _DeviceCard(
      device: device,
      isThis: device.id == thisId,
      showSwitch: supports,
      saving: view.saving.contains(device.id),
      onChanged: view.offline || view.saving.contains(device.id)
          ? null
          : (value) => _toggle(device, value),
      onOpen: () => _openDetails(device, thisId),
    );

    final hasOthers = arranged.others.isNotEmpty || arranged.stale.isNotEmpty;
    return ListView(
      padding: awListPadding(context, top: AwSpace.x2),
      children: [
        if (view.offline) const _OfflineLine(),
        _IntroCard(supported: supports, ringingCount: ringingCount),
        if (arranged.thisDevice case final self?) ...[
          _SectionLabel('settings.devices.sectionThis'.tr()),
          card(self),
        ],
        if (hasOthers) ...[
          _SectionLabel('settings.devices.sectionOther'.tr()),
          for (final device in arranged.others) card(device),
        ] else
          Padding(
            key: const Key('devices-single'),
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x1,
              AwSpace.x4,
              AwSpace.x1,
              AwSpace.x2,
            ),
            child: Text(
              'settings.devices.single'.tr(),
              style: context.awText.meta.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (arranged.stale.isNotEmpty) ...[
          _StaleToggle(
            count: arranged.stale.length,
            open: _staleOpen,
            onTap: () => setState(() => _staleOpen = !_staleOpen),
          ),
          if (_staleOpen)
            for (final device in arranged.stale) card(device),
        ],
        if (hasOthers) const _Footer(),
      ],
    );
  }
}

/// What removing a device means, under the list (ADR-0069 §6): its session
/// ends, and alarms it already set may still ring until it next opens.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = context.awText.meta.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      key: const Key('devices-footer'),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x1,
        AwSpace.x4,
        AwSpace.x1,
        AwSpace.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('settings.devices.footer'.tr(), style: style),
          const SizedBox(height: AwSpace.x1),
          Text('settings.devices.footerAlarms'.tr(), style: style),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AwSpace.x1,
      AwSpace.x4,
      AwSpace.x1,
      AwSpace.x1,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: context.awText.sectionLabel.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _OfflineLine extends StatelessWidget {
  const _OfflineLine();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('devices-offline'),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x1,
        AwSpace.x1,
        AwSpace.x1,
        AwSpace.x2,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: scheme.onSurface),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              'settings.devices.offline'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the switches do — or, on a server that has none, why there are none.
/// With two or more devices ringing, what that means is said here once
/// (X-06), not under every ringing row.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.supported, required this.ringingCount});

  final bool supported;
  final int ringingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface);
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: Key(supported ? 'devices-intro' : 'devices-unsupported'),
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: scheme.primary),
              const SizedBox(width: AwSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supported
                          ? 'settings.devices.intro'.tr()
                          : 'settings.devices.unsupported'.tr(),
                      style: textStyle,
                    ),
                    if (supported && ringingCount >= 2) ...[
                      const SizedBox(height: AwSpace.x2),
                      Text(
                        'settings.devices.multiHint'.tr(
                          args: {'count': '$ringingCount'},
                        ),
                        key: const Key('devices-multi-note'),
                        style: textStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaleToggle extends StatelessWidget {
  const _StaleToggle({
    required this.count,
    required this.open,
    required this.onTap,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x2),
      child: Semantics(
        button: true,
        expanded: open,
        child: InkWell(
          key: const Key('devices-stale-toggle'),
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AwSpace.x12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AwSpace.x1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'settings.devices.stale'.tr(args: {'count': '$count'}),
                      style: context.awText.sectionLabel.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One device: who it is on top, whether it rings below.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isThis,
    required this.showSwitch,
    required this.saving,
    required this.onChanged,
    required this.onOpen,
  });

  final DeviceInfo device;
  final bool isThis;
  final bool showSwitch;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  /// Opens the detail sheet (rename, remove or sign out).
  final VoidCallback onOpen;

  static IconData _icon(String platform) => switch (platform) {
    'ios' => Icons.phone_iphone,
    'android' => Icons.phone_android,
    'macos' => Icons.laptop_mac,
    'windows' => Icons.desktop_windows,
    'linux' => Icons.computer,
    'web' => Icons.language,
    _ => Icons.devices_other,
  };

  String _seen() {
    final at = device.lastSeenAt;
    final now = DateTime.now();
    if (isThis || (at != null && now.difference(at).inMinutes < 2)) {
      return 'settings.devices.activeNow'.tr();
    }
    if (at == null) return devicePlatformLabel(device.platform);
    return 'settings.devices.lastSeen'.tr(
      args: {'ago': awRelativePast(at, now)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = deviceDisplayName(device);
    final platform = devicePlatformLabel(device.platform);
    final seen = _seen();
    final rings = device.ringsUrgent == true;
    final web = device.platform == 'web';
    final metaStyle = context.awText.meta.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final thisLabel = 'settings.devices.thisDevice'.tr();

    final top = Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      onTap: onOpen,
      label: [name, if (isThis) thisLabel, platform, seen].join(', '),
      child: InkWell(
        key: Key('device-top-${device.id}'),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x4,
              vertical: AwSpace.x3,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _icon(device.platform),
                    size: 24,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AwSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AwSpace.x2,
                        runSpacing: AwSpace.x1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AwWordSafeText(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.awText.rowTitle.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          if (isThis) _ThisDeviceBadge(thisLabel),
                        ],
                      ),
                      const SizedBox(height: AwSpace.x1),
                      Text('$platform · $seen', style: metaStyle),
                    ],
                  ),
                ),
                const SizedBox(width: AwSpace.x2),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );

    final label = web
        ? 'settings.devices.ringSwitchWeb'.tr()
        : 'settings.devices.ringSwitch'.tr();
    // One short line at most: a tab rings only while it is open, and
    // whether an off tab gets a notification at all depends on the server's
    // browser push, so "arrives as a normal notification" is for the others.
    // Several ringing devices are explained once, under the intro (X-06).
    final hints = [
      if (web) 'settings.devices.webHint'.tr(),
      if (!rings && !web) 'settings.devices.offHint'.tr(),
    ];
    final switchRow = MergeSemantics(
      child: InkWell(
        key: Key('device-switch-row-${device.id}'),
        onTap: onChanged == null ? null : () => onChanged!(!rings),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AwSpace.x12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x4,
              vertical: AwSpace.x1,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        semanticsLabel: '$label, $name',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      for (final hint in hints) Text(hint, style: metaStyle),
                    ],
                  ),
                ),
                if (saving) ...[
                  SizedBox(
                    key: Key('device-saving-${device.id}'),
                    width: AwSpace.x4,
                    height: AwSpace.x4,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AwSpace.x2),
                ],
                Switch(
                  key: Key('device-switch-${device.id}'),
                  value: rings,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: Key('device-card-${device.id}'),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            if (showSwitch) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: context.awTokens.hairline,
              ),
              switchRow,
            ],
          ],
        ),
      ),
    );
  }
}

class _ThisDeviceBadge extends StatelessWidget {
  const _ThisDeviceBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('device-this-badge'),
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// A loading placeholder in a device card's shape. Still, no shimmer (G8).
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget bar(double width) => Container(
      width: width,
      height: AwSpace.x3,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
      ),
    );
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              ),
              const SizedBox(width: AwSpace.x3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140),
                  const SizedBox(height: AwSpace.x2),
                  bar(96),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
