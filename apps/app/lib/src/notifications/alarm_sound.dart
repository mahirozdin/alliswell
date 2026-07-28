/// The alarm bed the in-app ring screen loops (OPH-180, DESIGN §11 A3).
///
/// Round 9 exposed the gap: `AlarmFeedback` was haptics-only, so while the app
/// was open — the ONE moment we fully control — the alarm was silent, and on
/// desktop and web (where there is no OS alarm at all) nothing ever made a
/// sound. This is the audible half, behind a seam so tests stay quiet.
library;

import 'package:audioplayers/audioplayers.dart';

import 'sound_store.dart';

/// The bundled 28 s bed, as a Flutter asset (the OS lanes use their own
/// platform resources — see NOTIFICATIONS §2/§1).
const String kAlarmSoundAsset = 'audio/aw_alarm.m4a';

/// The seam between "make a loud noise until I say stop" and the audio plugin.
/// Widget tests inject silence; nothing platform-specific leaks upward.
abstract class AlarmSoundPlayer {
  /// Starts [asset] on repeat. Throws when the platform refuses (a browser's
  /// autoplay policy, a missing plugin) — the caller degrades honestly.
  Future<void> loop(String asset);

  Future<void> stop();

  Future<void> dispose();
}

/// The real player. Two platform knobs matter, and they are the reason this
/// package was chosen (ADR-0015 §7):
///
/// - **iOS `AVAudioSession` category `.playback`** — audio in this category is
///   heard even with the mute switch ON. That is legitimate here and only here:
///   the ring screen is in the FOREGROUND with the user looking at it. It is NOT
///   the background-audio-session trick pre-iOS-26 alarm apps use, which
///   NOTIFICATIONS §2b rejects.
/// - **Android `USAGE_ALARM`** — routes to the alarm stream, so it rings at
///   alarm volume rather than at whatever the media volume happens to be.
class AudioPlayersAlarmSound implements AlarmSoundPlayer {
  AudioPlayersAlarmSound({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    _configured = true;
  }

  @override
  Future<void> loop(String asset) async {
    await _configure();
    await _player.stop();
    await _player.play(AssetSource(asset), volume: 1);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// A sound the app ships. Each one exists in up to three shapes, because the
/// three surfaces that make noise cannot share a single file:
///
/// - **[inAppAsset]** — what the ring screen's player loops (any format).
/// - **[androidRaw]** — a `res/raw` resource, which is the only kind of file an
///   Android notification channel can point at without a content provider.
/// - **iOS** — either bundled in the app ([iosBundledName], wired into the
///   pbxproj) or installed into the app container's `Library/Sounds` at runtime
///   ([iosInstallAsset]). `UNNotificationSound` looks in the container FIRST,
///   which is what lets us add sounds without touching Xcode — and it only
///   accepts aiff/wav/caf, so these are `.caf` (IMA4).
class AwBundledSound {
  const AwBundledSound({
    required this.id,
    required this.inAppAsset,
    required this.androidRaw,
    required this.seconds,
    this.iosBundledName,
    this.iosInstallAsset,
  });

  final String id;
  final String inAppAsset;
  final String androidRaw;
  final double seconds;
  final String? iosBundledName;
  final String? iosInstallAsset;

  /// The name an iOS notification payload should carry, once installed.
  String? get iosSoundName =>
      iosBundledName ?? iosInstallAsset?.split('/').last;
}

/// The 28 s alarm bed, plus two short tones for ordinary reminders. The bed is
/// bundled (round 6 wired it into the pbxproj); the tones install themselves.
const List<AwBundledSound> kBundledSounds = [
  AwBundledSound(
    id: 'aw_alarm',
    inAppAsset: 'audio/aw_alarm.m4a',
    androidRaw: 'aw_alarm',
    iosBundledName: 'aw_alarm.caf',
    seconds: 28,
  ),
  AwBundledSound(
    id: 'chime',
    inAppAsset: 'audio/aw_chime.m4a',
    androidRaw: 'aw_chime',
    iosInstallAsset: 'assets/audio/aw_chime.caf',
    seconds: 1.6,
  ),
  AwBundledSound(
    id: 'ping',
    inAppAsset: 'audio/aw_ping.m4a',
    androidRaw: 'aw_ping',
    iosInstallAsset: 'assets/audio/aw_ping.caf',
    seconds: 0.9,
  ),
];

AwBundledSound? bundledSoundById(String id) {
  for (final sound in kBundledSounds) {
    if (sound.id == id) return sound;
  }
  return null;
}

/// What the user picked for one lane (alarm or reminder): the OS's own sound, a
/// sound we ship, or a file they uploaded (OPH-181).
class AwSoundChoice {
  const AwSoundChoice.os() : bundledId = null, fileId = null;
  const AwSoundChoice.bundled(String id) : bundledId = id, fileId = null;
  const AwSoundChoice.file(String id) : bundledId = null, fileId = id;

  final String? bundledId;
  final String? fileId;

  bool get isOsDefault => bundledId == null && fileId == null;

  String encode() {
    if (bundledId != null) return 'bundled:$bundledId';
    if (fileId != null) return 'file:$fileId';
    return 'os';
  }

  /// Junk, a retired id or a deleted file all resolve to the OS sound — never to
  /// silence (the `parseTaskTime` rule applied to audio).
  static AwSoundChoice parse(String? raw) {
    final value = (raw ?? '').trim();
    if (value.startsWith('bundled:')) {
      final id = value.substring('bundled:'.length);
      return bundledSoundById(id) == null
          ? const AwSoundChoice.os()
          : AwSoundChoice.bundled(id);
    }
    if (value.startsWith('file:')) {
      final id = value.substring('file:'.length);
      return id.isEmpty ? const AwSoundChoice.os() : AwSoundChoice.file(id);
    }
    return const AwSoundChoice.os();
  }
}

/// iOS notification-sound formats (NOTIFICATIONS §2c): aiff/wav/caf carrying
/// PCM, IMA4, µLaw or aLaw. **mp3 and m4a will not play** — a fact we tell the
/// user at upload time instead of letting them find out at 03:00.
const Set<String> kIosNotificationSoundExtensions = {
  'caf',
  'aiff',
  'aif',
  'wav',
};

/// The hard limit iOS puts on a notification sound.
const Duration kMaxNotificationSoundLength = Duration(seconds: 30);

/// What an uploaded file can be used for. Both answers are useful; only one of
/// them is an OS notification sound.
enum AwSoundUsability {
  /// Playable everywhere, including as the OS notification sound.
  everywhere,

  /// The in-app alarm bed can play it; iOS notifications cannot.
  inAppOnly,
}

/// Judges an upload by its NAME (the only thing we can check before it exists on
/// the device) — see [AwSoundUsability].
AwSoundUsability soundUsability(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return kIosNotificationSoundExtensions.contains(ext)
      ? AwSoundUsability.everywhere
      : AwSoundUsability.inAppOnly;
}

/// The sound name the CURRENT platform's notification lane should carry, plus an
/// honest reason when we could not give it the one the user chose.
class AwResolvedSound {
  const AwResolvedSound({this.name, this.degradedReason});

  /// iOS: a file name in the bundle or `Library/Sounds`. Android: a `res/raw`
  /// resource name. Null = the OS's own sound.
  final String? name;

  /// Non-null when the user's choice could not be honoured — logged to the alarm
  /// log and said out loud in Settings (never swallowed).
  final String? degradedReason;
}

/// Turns a [AwSoundChoice] into what the notification lane can actually play
/// (OPH-181, NOTIFICATIONS §2c). Pure except for the [SoundStore] it asks, so a
/// test can drive every platform branch.
class AlarmSoundResolver {
  const AlarmSoundResolver({
    required this.store,
    required this.isIos,
    required this.isAndroid,
  });

  final SoundStore store;
  final bool isIos;
  final bool isAndroid;

  Future<AwResolvedSound> resolve(AwSoundChoice choice) async {
    if (choice.isOsDefault) return const AwResolvedSound();

    final bundledId = choice.bundledId;
    if (bundledId != null) {
      final sound = bundledSoundById(bundledId);
      if (sound == null) return const AwResolvedSound();
      if (isAndroid) return AwResolvedSound(name: sound.androidRaw);
      if (!isIos) {
        // Desktop/web have no OS alarm lane worth naming a file for; the in-app
        // bed plays the same sound from its Flutter asset.
        return const AwResolvedSound();
      }
      if (sound.iosBundledName != null) {
        return AwResolvedSound(name: sound.iosBundledName);
      }
      // Ships as an asset and installs itself into the container.
      final installed = await store.installAsset(sound.iosInstallAsset!);
      if (installed == null) {
        return const AwResolvedSound(
          degradedReason: 'could not install bundled sound',
        );
      }
      return AwResolvedSound(name: installed);
    }

    final fileId = choice.fileId!;
    if (isAndroid) {
      // Android channels can only point at a res/raw resource or a content://
      // URI; a file in app-private storage is unreadable by the system UI, and
      // exposing one needs a FileProvider (native config, backlog). So a custom
      // sound plays in the in-app bed and the notification keeps the OS sound —
      // stated, not hidden.
      return const AwResolvedSound(
        degradedReason: 'android-custom-sound-unsupported',
      );
    }
    if (!isIos) return const AwResolvedSound();

    // Installed when the user picked it (see the settings picker). The guard
    // OPH-176 deferred to here: a name iOS cannot resolve degrades SILENTLY to
    // the default ding, so check before promising it.
    final name = await _installedNameFor(fileId);
    if (name == null) {
      return const AwResolvedSound(degradedReason: 'custom-sound-missing');
    }
    return AwResolvedSound(name: name);
  }

  Future<String?> _installedNameFor(String fileId) async {
    for (final name in await store.installed()) {
      if (name.startsWith('$fileId.')) return name;
    }
    return null;
  }
}
