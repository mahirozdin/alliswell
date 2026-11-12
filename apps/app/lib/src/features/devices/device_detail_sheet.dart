import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/persisted_prefs.dart' show dateFormatProvider;
import '../../i18n/i18n.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'data/device_api.dart';
import 'device_display_name.dart';
import 'providers.dart';

/// The longest name the sheet accepts (mobbin-alarm §2.4).
const int kDeviceNameMaxLength = 40;

/// What the person did in the sheet that the Devices screen has to finish.
sealed class DeviceSheetOutcome {
  const DeviceSheetOutcome();
}

/// "Sign out on this device": the screen runs the normal sign-out flow.
final class DeviceSheetSignOut extends DeviceSheetOutcome {
  const DeviceSheetSignOut();
}

/// Another device was removed (and so signed out).
final class DeviceSheetRemoved extends DeviceSheetOutcome {
  const DeviceSheetRemoved(this.removal);

  final DeviceRemoval removal;
}

/// The name saved when the field is left empty: the platform's own word —
/// or, for a browser whose stored name is its User-Agent, what that says.
String devicePlatformName(DeviceInfo device) {
  final shown = deviceDisplayName(device);
  final stored = device.name?.trim() ?? '';
  // A name the person set is shown as is; anything else already IS the
  // fallback.
  if (stored.isEmpty || shown != stored) return shown;
  return deviceDisplayName(
    DeviceInfo(id: device.id, platform: device.platform),
  );
}

/// Opens one device's details (#48, OPH-449): its name, the read-only facts
/// and the way to remove it — or, for this device, to sign out. The ring
/// switch is not repeated here; the list row is its one place.
Future<DeviceSheetOutcome?> showDeviceDetailSheet(
  BuildContext context, {
  required DeviceInfo device,
  required bool isThis,
  required bool offline,
}) => showModalBottomSheet<DeviceSheetOutcome>(
  context: context,
  // OPH-212: the ROOT navigator, above the shell's glass bar. A form is body
  // text, so the sheet is solid surface (DESIGN §3).
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AwRadius.xl)),
  ),
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) =>
      DeviceDetailSheet(device: device, isThis: isThis, offline: offline),
);

class DeviceDetailSheet extends ConsumerStatefulWidget {
  const DeviceDetailSheet({
    super.key,
    required this.device,
    required this.isThis,
    required this.offline,
  });

  final DeviceInfo device;
  final bool isThis;
  final bool offline;

  @override
  ConsumerState<DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends ConsumerState<DeviceDetailSheet> {
  late final TextEditingController _name = TextEditingController(
    text: _clip(deviceDisplayName(widget.device)),
  );
  bool _busy = false;
  String? _error;

  static String _clip(String name) => name.length > kDeviceNameMaxLength
      ? name.substring(0, kDeviceNameMaxLength)
      : name;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final typed = _name.text.trim();
    final name = typed.isEmpty
        ? _clip(devicePlatformName(widget.device))
        : typed;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(devicesProvider.notifier)
        .rename(widget.device.id, name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = 'settings.devices.saveFailed'.tr();
    });
  }

  Future<void> _remove() async {
    final device = widget.device;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          key: const Key('device-remove-dialog'),
          title: Text(
            'settings.devices.removeConfirm'.tr(
              args: {'device': deviceDisplayName(device)},
            ),
          ),
          content: Text(
            device.hasSession == false
                ? 'settings.devices.removeNoSession'.tr()
                : 'settings.devices.removeBody'.tr(),
          ),
          actions: [
            TextButton(
              key: const Key('device-remove-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('settings.devices.removeKeep'.tr()),
            ),
            FilledButton(
              key: const Key('device-remove-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('settings.devices.removeAction'.tr()),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final removal = await ref.read(devicesProvider.notifier).remove(device.id);
    if (!mounted) return;
    if (removal != null) {
      Navigator.of(context).pop(DeviceSheetRemoved(removal));
      return;
    }
    setState(() {
      _busy = false;
      _error = 'settings.devices.removeFailed'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final device = widget.device;
    final format = ref.watch(dateFormatProvider);
    final now = DateTime.now();
    String when(DateTime at) =>
        awFormatDateTime(at.toLocal(), format: format, now: now);
    final metaStyle = context.awText.meta.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final platform = [
      devicePlatformLabel(device.platform),
      if (device.appVersion case final version? when version.isNotEmpty)
        'AllisWell $version',
    ].join(' · ');
    final seenAt = device.lastSeenAt;
    final addedAt = device.createdAt;
    final canChange = !widget.offline && !_busy;

    return Padding(
      key: const Key('device-detail-sheet'),
      padding: EdgeInsets.fromLTRB(
        AwSpace.x4,
        0,
        AwSpace.x4,
        AwSpace.x4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              deviceDisplayName(device),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            TextField(
              key: const Key('device-name-field'),
              controller: _name,
              enabled: canChange,
              maxLength: kDeviceNameMaxLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kDeviceNameMaxLength),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: canChange ? (_) => _save() : null,
              decoration: InputDecoration(
                labelText: 'settings.devices.rename'.tr(),
                hintText: _clip(devicePlatformName(device)),
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('device-name-save'),
                onPressed: canChange ? _save : null,
                child: Text('common.save'.tr()),
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            Text(
              'settings.devices.detailPlatform'.tr(args: {'value': platform}),
              key: const Key('device-detail-platform'),
              style: metaStyle,
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              'settings.devices.detailSeen'.tr(
                args: {
                  'value': widget.isThis
                      ? 'settings.devices.activeNow'.tr()
                      : seenAt == null
                      ? '—'
                      : when(seenAt),
                },
              ),
              key: const Key('device-detail-seen'),
              style: metaStyle,
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              'settings.devices.detailAdded'.tr(
                args: {
                  'value': addedAt == null
                      ? '—'
                      : awFormatDate(
                          addedAt.toLocal(),
                          format: format,
                          now: now,
                        ),
                },
              ),
              key: const Key('device-detail-added'),
              style: metaStyle,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: AwSpace.x3),
              Text(
                error,
                key: const Key('device-detail-error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            const SizedBox(height: AwSpace.x6),
            SizedBox(
              height: 48,
              child: widget.isThis
                  ? FilledButton(
                      key: const Key('device-sign-out-here'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(const DeviceSheetSignOut()),
                      child: Text('settings.devices.signOutHere'.tr()),
                    )
                  : FilledButton(
                      key: const Key('device-remove'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                      onPressed: canChange ? _remove : null,
                      child: Text('settings.devices.remove'.tr()),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
