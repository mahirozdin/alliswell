/// The alarm bed the in-app ring screen loops (OPH-180, DESIGN §11 A3).
///
/// Round 9 exposed the gap: `AlarmFeedback` was haptics-only, so while the app
/// was open — the ONE moment we fully control — the alarm was silent, and on
/// desktop and web (where there is no OS alarm at all) nothing ever made a
/// sound. This is the audible half, behind a seam so tests stay quiet.
library;

import 'package:audioplayers/audioplayers.dart';

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
