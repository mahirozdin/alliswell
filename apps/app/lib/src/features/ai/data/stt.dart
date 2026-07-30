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
  const SttInit({required this.available, required this.onDevice, this.error});
  final bool available;
  final bool onDevice;
  final String? error;
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
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _onDevice = false;

  @override
  Future<SttInit> initialize() async {
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
