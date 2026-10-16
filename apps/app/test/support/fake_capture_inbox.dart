import 'dart:async';

import 'package:alliswell/src/features/tasks/data/capture_inbox.dart';

/// The Siri/Shortcuts mailbox, faked (OPH-376, ADR-0057).
///
/// Counts every [take] for the same reason `FakeShareInbox` does: the drain
/// runs at bind, on resume, on the native `changed` signal and when the
/// workspace arrives, so the bug to catch is one request read twice.
class FakeCaptureInbox implements CaptureInbox {
  FakeCaptureInbox({List<AwCapture>? pending}) : pending = [...?pending];

  final List<AwCapture> pending;
  int takes = 0;
  final _changes = StreamController<void>.broadcast();

  /// Simulates an App Intent parking a request while the app is in front.
  void deliver(AwCapture capture, {bool signal = true}) {
    pending.add(capture);
    if (signal) _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<AwCapture>> take() async {
    takes++;
    final out = [...pending];
    pending.clear(); // read-and-clear, exactly like the native side
    return out;
  }

  Future<void> dispose() => _changes.close();
}
