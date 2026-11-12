import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/route_leading.dart';
import '../../widgets/status_views.dart';
import 'data/device_api.dart';
import 'device_display_name.dart';
import 'providers.dart';

/// The device the pick page starts on: the one the server promoted after the
/// removal (it rings now), else the most recently seen device that is not a
/// browser tab, else the most recently seen one (mobbin-alarm §2.5).
String? preselectAlarmDevice(List<DeviceInfo> devices) {
  for (final device in devices) {
    if (device.ringsUrgent == true) return device.id;
  }
  DeviceInfo? newest(Iterable<DeviceInfo> pool) {
    DeviceInfo? best;
    for (final d in pool) {
      final at = d.lastSeenAt;
      final bestAt = best?.lastSeenAt;
      if (best == null ||
          (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        best = d;
      }
    }
    return best;
  }

  return (newest(devices.where((d) => d.platform != 'web')) ?? newest(devices))
      ?.id;
}

/// "Acil alarmlar hangi cihazda çalsın?" (#48, OPH-449) — opened after the
/// only ringing device was removed, so urgent alarms never go quiet without
/// the person seeing it. The server has already promoted a device; this page
/// shows that choice selected and lets the person keep or change it.
///
/// Resolves true when the choice was saved.
class PickAlarmDevicePage extends ConsumerStatefulWidget {
  const PickAlarmDevicePage({super.key, required this.devices, this.thisId});

  /// The devices left on the account, as the server listed them.
  final List<DeviceInfo> devices;

  /// This install's id, so its row can say so.
  final String? thisId;

  @override
  ConsumerState<PickAlarmDevicePage> createState() =>
      _PickAlarmDevicePageState();
}

class _PickAlarmDevicePageState extends ConsumerState<PickAlarmDevicePage> {
  late String? _selected = preselectAlarmDevice(widget.devices);
  bool _busy = false;

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(devicesProvider.notifier).ringOnlyOn(selected);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = false);
    messenger?.showSnackBar(
      SnackBar(content: Text('settings.devices.saveFailed'.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metaStyle = context.awText.meta.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Scaffold(
      key: const Key('pick-alarm-device-page'),
      appBar: AppBar(leading: awRouteLeading(context)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AwSpace.x1),
                child: Semantics(
                  header: true,
                  child: Text(
                    'settings.devices.pickTitle'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AwSpace.x2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AwSpace.x1),
                child: Text(
                  'settings.devices.pickBody'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              Card(
                clipBehavior: Clip.antiAlias,
                child: RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (id) {
                    if (_busy || id == null) return;
                    setState(() => _selected = id);
                  },
                  child: Column(
                    children: [
                      for (final device in widget.devices)
                        RadioListTile<String>(
                          key: Key('pick-device-${device.id}'),
                          value: device.id,
                          enabled: !_busy,
                          title: Text(
                            deviceDisplayName(device),
                            style: context.awText.rowTitle.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            [
                              devicePlatformLabel(device.platform),
                              if (device.id == widget.thisId)
                                'settings.devices.thisDevice'.tr(),
                            ].join(' · '),
                            style: metaStyle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AwSpace.x4),
              SizedBox(
                height: 56,
                child: FilledButton(
                  key: const Key('pick-device-save'),
                  onPressed: _busy || _selected == null ? null : _save,
                  child: Text('common.save'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
