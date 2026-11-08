import 'dart:async';

import 'package:alliswell/src/features/ai/data/stt.dart';

/// A scripted SttController for tests (OPH-223) — no platform channel. Feed it
/// partials and a final; it records calls so tests can assert the wiring.
class FakeSttController implements SttController {
  FakeSttController({
    this.available = true,
    this.onDevice = true,
    this.noMicrophone = false,
    this.startError,
    this.localesList = const [
      SttLocale(id: 'tr_TR', name: 'Türkçe'),
      SttLocale(id: 'en_US', name: 'English'),
    ],
  });

  final bool available;
  final bool onDevice;

  /// R-10: answer like a device with no audio input at all.
  final bool noMicrophone;

  /// R-10: [start] throws this (a recognizer that refuses to start).
  final Object? startError;
  final List<SttLocale> localesList;

  final List<String> calls = [];
  void Function(String text, bool isFinal)? _onResult;

  /// Holds [initialize] open — the OS permission prompt still on screen
  /// (OPH-402). Complete it to answer the prompt.
  Completer<void>? initGate;

  @override
  Future<SttInit> initialize() async {
    calls.add('initialize');
    final gate = initGate;
    if (gate != null) await gate.future;
    return SttInit(
      available: available && !noMicrophone,
      onDevice: onDevice,
      noMicrophone: noMicrophone,
    );
  }

  @override
  Future<List<SttLocale>> locales() async => localesList;

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    calls.add('start:$localeId');
    final error = startError;
    if (error != null) throw error;
    _onResult = onResult;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> cancel() async => calls.add('cancel');

  /// Test drivers.
  void emitPartial(String text) => _onResult?.call(text, false);
  void emitFinal(String text) => _onResult?.call(text, true);
}
