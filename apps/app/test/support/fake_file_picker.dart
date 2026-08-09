import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;

import 'package:alliswell/src/features/files/providers.dart';

/// A picker that records WHICH named way was asked for (OPH-244).
///
/// The bug this round fixed was a call that never said what it wanted, so
/// "which picker opened" is now the thing worth asserting — not just "some
/// files came back". Every test that taps an attach affordance can check the
/// intent instead of trusting the label.
class RecordingFilePicker {
  RecordingFilePicker({
    this.picks = const [],
    this.bySource = const {},
    this.throws = false,
  });

  /// What every source returns unless [bySource] overrides it.
  final List<PickedUpload> picks;

  /// Per-source answers, for tests that drive more than one path.
  final Map<AttachSource, List<PickedUpload>> bySource;

  /// Simulates a picker the platform could not open (DESIGN §30 A8).
  final bool throws;

  /// Every source asked for, in order.
  final List<AttachSource> calls = [];

  Future<List<PickedUpload>> call(AttachSource source) async {
    calls.add(source);
    if (throws) throw PlatformException(code: 'unavailable');
    return bySource[source] ?? picks;
  }
}

/// A tiny in-memory pick, the shape every attachment test wants.
PickedUpload filePick(String name, {int size = 64}) => PickedUpload.fromBytes(
  name: name,
  bytes: Uint8List.fromList(List.filled(size, 1)),
);
