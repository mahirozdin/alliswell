import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/files/providers.dart';
import '../../features/workspaces/workspaces.dart';
import '../../i18n/i18n.dart';
import '../../notifications/alarm_sound.dart';
import '../../notifications/providers.dart';
import '../../notifications/sound_store.dart';
import '../../theme/tokens.dart';

/// The folder uploaded ringtones live in (OPH-181). A reserved workspace folder,
/// so the sounds are ordinary files — visible in Dosyalar, synced, deletable —
/// instead of a hidden store nobody can audit.
const String kRingtoneFolderName = 'Zil sesleri';

/// Which lane a picker is choosing for.
enum SoundLane { alarm, reminder }

/// Picks the sound for one lane: the OS's own, one we ship, or a file the user
/// uploaded (DESIGN §18 N6 — you choose a sound by HEARING it).
Future<void> showSoundPicker(BuildContext context, SoundLane lane) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => _SoundPickerSheet(lane: lane),
    );

class _SoundPickerSheet extends ConsumerStatefulWidget {
  const _SoundPickerSheet({required this.lane});

  final SoundLane lane;

  @override
  ConsumerState<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends ConsumerState<_SoundPickerSheet> {
  bool _busy = false;
  String? _previewing;

  /// One place decides what a picked value means (the RadioGroup contract).
  Future<void> _pick(String? value, List<FileAttachment> uploaded) async {
    if (value == null || _busy) return;
    if (value.startsWith('file:')) {
      final id = value.substring('file:'.length);
      final file = uploaded.where((f) => f.id == id).firstOrNull;
      if (file != null) await _selectFile(file);
      return;
    }
    await _save(AwSoundChoice.parse(value));
  }

  Future<void> _save(AwSoundChoice choice) async {
    final notifier = widget.lane == SoundLane.alarm
        ? ref.read(alarmSoundRawProvider.notifier)
        : ref.read(reminderSoundRawProvider.notifier);
    await notifier.set(choice.encode());
  }

  /// Bundled sounds preview straight from their Flutter asset.
  Future<void> _preview(AwBundledSound sound) async {
    setState(() => _previewing = sound.id);
    final player = AudioPlayersAlarmSound();
    try {
      await player.loop(sound.inAppAsset);
      await Future<void>.delayed(
        Duration(milliseconds: (sound.seconds * 1000).clamp(500, 4000).toInt()),
      );
    } on Object {
      // A platform that cannot preview is not a reason to block the choice.
    } finally {
      await player.stop();
      await player.dispose();
      if (mounted) setState(() => _previewing = null);
    }
  }

  /// Selecting an uploaded sound INSTALLS it (OPH-181): iOS resolves a
  /// notification sound from the app container, so the bytes have to be there
  /// before the alarm needs them — and if the install fails we say so instead of
  /// storing a choice that will silently ring the default ding.
  Future<void> _selectFile(FileAttachment file) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(fileUrlCacheProvider).urlFor(file.id);
      if (url == null) throw StateError('no url');
      final response = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null) throw StateError('no bytes');
      final dot = file.name.lastIndexOf('.');
      final ext = dot < 0 ? 'caf' : file.name.substring(dot + 1);
      final installed = await soundStore.installBytes('${file.id}.$ext', bytes);
      if (installed == null &&
          soundUsability(file.name) == AwSoundUsability.everywhere) {
        // Only worth complaining about when this file COULD have been an OS
        // sound; an in-app-only file never needed installing.
        messenger.showSnackBar(
          SnackBar(content: Text('sound.installFailed'.tr())),
        );
      }
      await _save(AwSoundChoice.file(file.id));
      if (soundUsability(file.name) == AwSoundUsability.inAppOnly) {
        messenger.showSnackBar(
          SnackBar(content: Text('sound.inAppOnlyPicked'.tr())),
        );
      }
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('sound.installFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Uploads a sound into the reserved folder, creating it on first use.
  Future<void> _upload() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final workspaces = await ref.read(workspacesProvider.future);
      if (workspaces.isEmpty) return;
      final workspaceId = workspaces.first.id;
      final folders = ref.read(foldersProvider).value ?? const [];
      var folderId = folders
          .where((f) => f.parentId == null && f.name == kRingtoneFolderName)
          .map((f) => f.id)
          .firstOrNull;
      folderId ??= await ref
          .read(folderStoreProvider)
          .create(workspaceId, kRingtoneFolderName);

      final picked = await ref.read(filePickerProvider)();
      for (final source in picked) {
        if (soundUsability(source.name) == AwSoundUsability.inAppOnly) {
          // Said at upload time (N6), not discovered at 03:00.
          messenger.showSnackBar(
            SnackBar(content: Text('sound.inAppOnlyUpload'.tr())),
          );
        }
        await ref
            .read(uploadsProvider.notifier)
            .start(
              workspaceId: workspaceId,
              targetType: 'workspace',
              targetId: workspaceId,
              folderId: folderId,
              source: source,
            );
      }
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('sound.uploadFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choice = widget.lane == SoundLane.alarm
        ? ref.watch(alarmSoundChoiceProvider)
        : ref.watch(reminderSoundChoiceProvider);
    final folders = ref.watch(foldersProvider).value ?? const [];
    final folderId = folders
        .where((f) => f.parentId == null && f.name == kRingtoneFolderName)
        .map((f) => f.id)
        .firstOrNull;
    final uploaded = folderId == null
        ? const <FileAttachment>[]
        : (ref.watch(workspaceLevelFilesProvider(folderId)).value ??
              const <FileAttachment>[]);

    return SafeArea(
      child: RadioGroup<String>(
        groupValue: choice.encode(),
        onChanged: (value) => _pick(value, uploaded),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AwSpace.x4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                AwSpace.x1,
                AwSpace.x4,
                AwSpace.x2,
              ),
              child: Text(
                widget.lane == SoundLane.alarm
                    ? 'sound.alarmTitle'.tr()
                    : 'sound.reminderTitle'.tr(),
                style: theme.textTheme.titleMedium,
              ),
            ),
            RadioListTile<String>(
              key: const Key('sound-os'),
              value: 'os',
              title: Text('sound.osDefault'.tr()),
            ),
            for (final sound in kBundledSounds)
              RadioListTile<String>(
                key: Key('sound-bundled-${sound.id}'),
                value: 'bundled:${sound.id}',
                title: Text('sound.bundled.${sound.id}'.tr()),
                secondary: IconButton(
                  key: Key('sound-preview-${sound.id}'),
                  tooltip: 'sound.preview'.tr(),
                  icon: Icon(
                    _previewing == sound.id
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  onPressed: _previewing != null ? null : () => _preview(sound),
                ),
              ),
            const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
              child: Text(
                'sound.yours'.tr(),
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (uploaded.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x4,
                  AwSpace.x2,
                  AwSpace.x4,
                  0,
                ),
                child: Text(
                  'sound.noneYet'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final file in uploaded)
              RadioListTile<String>(
                key: Key('sound-file-${file.id}'),
                value: 'file:${file.id}',
                title: Text(file.name),
                subtitle:
                    soundUsability(file.name) == AwSoundUsability.inAppOnly
                    ? Text('sound.inAppOnlyBadge'.tr())
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                AwSpace.x2,
                AwSpace.x4,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('sound-upload'),
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text('sound.upload'.tr()),
                ),
              ),
            ),
            // The platform truth, stated once, where the decision is made (N7).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                AwSpace.x2,
                AwSpace.x4,
                0,
              ),
              child: Text(
                'sound.rules'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a settings row shows for the current choice — the sound's own name, not
/// its id (OPH-181, DESIGN §17 D2's rule applied to sounds).
String soundChoiceLabel(AwSoundChoice choice) {
  if (choice.bundledId != null) return 'sound.bundled.${choice.bundledId}'.tr();
  if (choice.fileId != null) return 'sound.yours'.tr();
  return 'sound.osDefault'.tr();
}
