import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// On-device speech-to-text, behind a seam (OPH-223, ADR-0023). The rest of the
/// app talks only to [SttController]; tests inject a fake. `sttProvider` is
/// nullable — a null client means "voice unavailable here" (web, or a device
/// that has no recognizer), and the FAB falls back to text mode.

class SttLocale {
  const SttLocale({required this.id, required this.name});
  final String id;
  final String name;
}

class SttInit {
  const SttInit({
    required this.available,
    required this.onDevice,
    this.error,
    this.noMicrophone = false,
  });
  final bool available;
  final bool onDevice;
  final String? error;

  /// R-10 (OPH-402): the device has no audio input at all (a simulator on a
  /// Mac without a microphone). Distinct from a denied permission, so the
  /// sheet can say which one it is.
  final bool noMicrophone;
}

/// Asks the platform whether any audio input exists, BEFORE the recognizer
/// touches the microphone (R-10, OPH-402).
///
/// Why it has to come first: on iOS `speech_to_text`'s `listen` reads
/// `AVAudioEngine.inputNode`. With no input device, AudioToolbox waits on an
/// RPC that never answers and calls `abort()` about six seconds later
/// (`_ReportRPCTimeout`, SIGABRT). That is a native abort, not an exception:
/// no `try`/`catch` in Dart or Swift can catch it, and the plugin's
/// `initialize`/`hasPermission` say yes (they check the permission and the
/// recognizer, not the hardware). So the only safe answer is not to start.
///
/// `true`/`false` is the platform's answer (iOS:
/// `AVAudioSession.isInputAvailable`, `ios/Runner/AppDelegate.swift`). `null`
/// means "nobody here can tell" (no handler on Android/macOS, where a missing
/// microphone comes back as a recognizer error instead of a crash): the
/// caller goes on as before.
typedef AudioInputProbe = Future<bool?> Function();

const audioInputChannel = MethodChannel('alliswell/audio_input');

Future<bool?> platformAudioInputAvailable() async {
  try {
    return await audioInputChannel.invokeMethod<bool>('isInputAvailable');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

abstract class SttController {
  /// Initializes the engine (triggers the iOS two-part permission dialog).
  Future<SttInit> initialize();

  Future<List<SttLocale>> locales();

  /// Starts listening. `onResult(text, isFinal)` streams partials then a final;
  /// `onSoundLevel` drives the waveform. `pauseFor` is the VAD silence window.
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    Duration pauseFor = const Duration(seconds: 2),
  });

  /// Stops and lets the final result arrive.
  Future<void> stop();

  /// Discards the recording (the swipe-cancel path).
  Future<void> cancel();
}

/// The real controller over `speech_to_text`. Never referenced in tests.
class SpeechToTextController implements SttController {
  SpeechToTextController({AudioInputProbe? hasAudioInput})
    : _hasAudioInput = hasAudioInput ?? platformAudioInputAvailable;

  final AudioInputProbe _hasAudioInput;
  stt.SpeechToText? _plugin;
  stt.SpeechToText get _speech => _plugin ??= stt.SpeechToText();
  bool _onDevice = false;

  @override
  Future<SttInit> initialize() async {
    // R-10: no microphone → never reach the plugin (see AudioInputProbe).
    if (await _hasAudioInput() == false) {
      return const SttInit(
        available: false,
        onDevice: false,
        noMicrophone: true,
      );
    }
    try {
      final available = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      return SttInit(available: available, onDevice: _onDevice);
    } catch (e) {
      return SttInit(available: false, onDevice: false, error: e.toString());
    }
  }

  @override
  Future<List<SttLocale>> locales() async {
    final list = await _speech.locales();
    return [for (final l in list) SttLocale(id: l.localeId, name: l.name)];
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    await _speech.listen(
      onSoundLevelChange: onSoundLevel,
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        localeId: localeId,
        // Prefer on-device when the platform offers it (privacy-clean).
        onDevice: true,
      ),
    );
    _onDevice = _speech.isListening;
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// Nullable so tests inject a fake (the aiStreamClient pattern). Default: the
/// real controller on mobile/desktop.
final sttProvider = Provider<SttController?>((ref) => SpeechToTextController());
