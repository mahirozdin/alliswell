import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/files/providers.dart';
import '../../features/files/ui/attach_menu.dart';
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

/// The picker's preview player, behind a seam (OPH-190).
///
/// Round 10 #5 found three defects that all came from one shape: the player was
/// built inside the preview method, so nothing outside it could ever reach it.
/// A player that lives in the sheet's state can be stopped by the stop button,
/// swapped by the next sound, and silenced by `dispose()`. Injectable so tests
/// can assert the start/stop ORDER without an audio plugin.
final soundPreviewPlayerProvider = Provider<AlarmSoundPlayer Function()>(
  (_) => AudioPlayersAlarmSound.new,
);

/// Picks the sound for one lane: the OS's own, one we ship, or a file the user
/// uploaded (DESIGN §18 N6 — you choose a sound by HEARING it).
Future<void> showSoundPicker(BuildContext context, SoundLane lane) =>
    showModalBottomSheet<void>(
      context: context,
      // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
      // renders UNDER the shell's own glass bar and FAB — they are painted by
      // the Scaffold that owns the branch, above its body.
      useRootNavigator: true,
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

  /// Owned by the STATE, not by the method that starts it (OPH-190). This is
  /// the whole fix: a player nobody else can reach is a player nobody can stop.
  AlarmSoundPlayer? _player;

  /// A cancellable [Timer], not an awaited `Future.delayed`: a delay you cannot
  /// cancel keeps running after the preview it belongs to is gone, and would
  /// silence whatever the user started next.
  Timer? _autoStop;

  @override
  void dispose() {
    // Leaving the screen silences it. Until now the sheet closed and the sound
    // played on until its own delay expired — audio outliving the surface that
    // started it is the one outcome DESIGN §18 N6 forbids.
    _autoStop?.cancel();
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(player.stop().then((_) => player.dispose()));
    }
    super.dispose();
  }

  /// Stops whatever is playing. Safe to call when nothing is.
  Future<void> _stopPreview() async {
    _autoStop?.cancel();
    _autoStop = null;
    final player = _player;
    _player = null;
    if (mounted) setState(() => _previewing = null);
    if (player == null) return;
    await player.stop();
    await player.dispose();
  }

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

  /// Plays [asset] as the preview for [id], replacing whatever was playing.
  ///
  /// Tapping a second sound switches immediately (round 10 #5: every button
  /// used to be disabled until the first one ran out). The stop-first ordering
  /// is what makes that true, and the test asserts it.
  Future<void> _preview(
    String id,
    String asset, {
    required double seconds,
  }) async {
    await _stopPreview();
    if (!mounted) return;
    final player = ref.read(soundPreviewPlayerProvider)();
    _player = player;
    setState(() => _previewing = id);
    try {
      await player.loop(asset);
    } on Object {
      // A platform that cannot preview is not a reason to block the choice —
      // but it must not look like it is playing either.
      await _stopPreview();
      return;
    }
    // A superseded preview already had its timer cancelled by `_stopPreview`,
    // so this only ever stops the sound it belongs to.
    if (_player != player) return;
    // Long enough to recognise the sound, short enough not to become the alarm.
    _autoStop = Timer(
      Duration(milliseconds: (seconds * 1000).clamp(500, 4000).toInt()),
      () => unawaited(_stopPreview()),
    );
  }

  /// The bundled tones play straight from their Flutter asset.
  Future<void> _previewBundled(AwBundledSound sound) =>
      _preview('bundled:${sound.id}', sound.inAppAsset, seconds: sound.seconds);

  /// An uploaded ringtone previews too (OPH-190). It had no preview at all,
  /// which made "you choose a sound by hearing it" (N6) true for half the
  /// library — you could only audition the ones we shipped.
  Future<void> _previewFile(FileAttachment file) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(fileUrlCacheProvider).urlFor(file.id);
      if (url == null) throw StateError('no url');
      if (!mounted) return;
      await _preview('file:${file.id}', url, seconds: 4);
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('sound.previewFailed'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final messenger = ScaffoldMessenger.of(context);
    // OPH-244: pick BEFORE the spinner. The picker is a full-screen system UI;
    // showing a busy state behind it just means the sheet looks stuck for as
    // long as the user browses. And it asks for audio now — it used to open an
    // unfiltered file browser to choose a ringtone.
    final picked = await pickFrom(context, ref, AttachSource.audioFiles);
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
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
                secondary: _PreviewButton(
                  id: 'bundled:${sound.id}',
                  buttonKey: Key('sound-preview-${sound.id}'),
                  playing: _previewing,
                  onPlay: () => _previewBundled(sound),
                  onStop: _stopPreview,
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
                secondary: _PreviewButton(
                  id: 'file:${file.id}',
                  buttonKey: Key('sound-preview-file-${file.id}'),
                  playing: _previewing,
                  onPlay: () => _previewFile(file),
                  onStop: _stopPreview,
                ),
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

/// Play/stop for one row (OPH-190, DESIGN §18 N6).
///
/// The old button changed its icon to "stop" and then set `onPressed: null` —
/// it LOOKED like a stop control and did nothing, and while it looked that way
/// every other sound's button was disabled too. The rule this widget encodes:
/// **the button always does what its icon says**, and only the row that is
/// actually playing shows stop.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.id,
    required this.buttonKey,
    required this.playing,
    required this.onPlay,
    required this.onStop,
  });

  final String id;
  final Key buttonKey;
  final String? playing;
  final VoidCallback onPlay;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final isPlaying = playing == id;
    return IconButton(
      key: buttonKey,
      tooltip: isPlaying ? 'sound.stopPreview'.tr() : 'sound.preview'.tr(),
      icon: Icon(
        isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline,
      ),
      // Never null: a disabled control that renders as "stop" is a lie, and
      // another row's preview must not lock this one out.
      onPressed: isPlaying ? () => onStop() : onPlay,
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
