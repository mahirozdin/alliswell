import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../core/tr_locative.dart';
import '../../i18n/i18n.dart';
import '../../sync/providers.dart' show syncClientIdProvider;
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';
import '../workspaces/workspaces.dart' show currentUserIdProvider;
import 'data/device_api.dart';
import 'device_display_name.dart';
import 'providers.dart';

/// localKv prefix of the "card already answered" flag; the full key adds the
/// account and this install, so each pair sees the card once.
const String kNewDeviceCardKeyPrefix = 'alliswell_new_device_card.';

String newDeviceCardKey(String userId, String deviceId) =>
    '$kNewDeviceCardKeyPrefix$userId.$deviceId';

/// Where the card keeps its flag; a test hands it its own store.
final newDeviceCardKvProvider = Provider<LocalKv>((_) => localKv);

/// Whether this account + install already answered the card.
final _newDeviceCardSeenProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, key) async =>
          await ref.watch(newDeviceCardKvProvider).get(key) != null,
    );

/// The device the card names, or null when there is no card to show: this
/// device is listed and does not ring while another does (#48, owner answer
/// 5). With several ringing, the most recently seen one is named.
DeviceInfo? newDeviceCardRinger(DevicesView view, String thisId) {
  if (!view.supportsRingsUrgent) return null;
  final self = view.byId(thisId);
  if (self == null || self.ringsUrgent != false) return null;
  DeviceInfo? named;
  for (final device in view.ringing) {
    if (device.id == thisId) continue;
    final at = device.lastSeenAt;
    final namedAt = named?.lastSeenAt;
    if (named == null ||
        (at != null && (namedAt == null || at.isAfter(namedAt)))) {
      named = device;
    }
  }
  return named;
}

/// "Bu cihazda acil alarmlar kapalı. Alarmlar iPhone 16’da çalıyor."
/// [Bu cihazda da çal] [Tamam] — once per account and install, so a device
/// that joined switched off learns where its alarms ring without opening
/// Settings (#48, OPH-449). Builds nothing when there is nothing to say.
class NewDeviceAlarmCard extends ConsumerStatefulWidget {
  const NewDeviceAlarmCard({super.key});

  @override
  ConsumerState<NewDeviceAlarmCard> createState() => _NewDeviceAlarmCardState();
}

class _NewDeviceAlarmCardState extends ConsumerState<NewDeviceAlarmCard> {
  bool _busy = false;
  bool _closed = false;

  Future<void> _answer(String key) async {
    await ref.read(newDeviceCardKvProvider).set(key, '1');
    if (!mounted) return;
    setState(() => _closed = true);
  }

  Future<void> _turnOn(String key, String thisId) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(devicesProvider.notifier)
        .setRingsUrgent(thisId, true);
    if (!mounted) return;
    if (result == null) {
      setState(() => _busy = false);
      messenger?.showSnackBar(
        SnackBar(content: Text('settings.devices.saveFailed'.tr())),
      );
      return;
    }
    await _answer(key);
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final userId = ref.watch(currentUserIdProvider);
    final thisId = ref.watch(syncClientIdProvider.select((id) => id.value));
    final view = ref.watch(devicesProvider).value;
    // An offline list is the last one this session saw: it cannot tell what
    // changed meanwhile, so it brings up nothing new (OPH-453).
    if (userId == null || thisId == null || view == null || view.offline) {
      return const SizedBox.shrink();
    }
    final ringer = newDeviceCardRinger(view, thisId);
    if (ringer == null) return const SizedBox.shrink();
    final key = newDeviceCardKey(userId, thisId);
    if (ref.watch(_newDeviceCardSeenProvider(key)).value != false) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final device = awAt(
      deviceDisplayName(ringer),
      languageCode: AwI18n.instance.locale.languageCode,
    );
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: const Key('new-device-alarm-card'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notifications_paused_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AwSpace.x3),
                  Expanded(
                    child: Text(
                      'settings.devices.newDeviceCard'.tr(
                        args: {'device': device},
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AwSpace.x2),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AwSpace.x2,
                children: [
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      key: const Key('new-device-card-ok'),
                      onPressed: _busy ? null : () => _answer(key),
                      child: Text('common.ok'.tr()),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      key: const Key('new-device-card-turn-on'),
                      onPressed: _busy ? null : () => _turnOn(key, thisId),
                      child: Text('settings.devices.newDeviceTurnOn'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
