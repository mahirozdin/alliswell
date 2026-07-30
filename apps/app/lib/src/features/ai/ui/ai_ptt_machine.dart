/// The press-to-talk gesture machine (OPH-223, DESIGN §24 AI2) — PURE: no
/// timers, no platform. The FAB widget owns the 250 ms hold timer and feeds
/// events in; the plugin owns the 2 s VAD. This is what makes the whole gesture
/// (hold ≥250 ms → record; lift → LOCKED, bubble stays open — the owner's rule;
/// swipe left ≥80 px → cancel; tap <250 ms → text mode) testable off-device.
library;

enum AiPttPhase { idle, pressed, recording, locked, cancelled }

/// Side effects the widget must perform; the machine only decides them.
enum AiPttAction {
  openBubbleComposing, // tap path: text + mic toggle
  openBubbleListening, // hold path: start recording UI
  startStt,
  finalizeStt,
  cancelStt,
  hapticStart,
  hapticCancel,
}

/// The left-swipe distance (px) that cancels an in-progress recording.
const double kAiPttCancelDx = 80;

/// The press duration (ms) that promotes a press into a recording.
const int kAiPttHoldMs = 250;

class AiPttMachine {
  AiPttPhase phase = AiPttPhase.idle;
  double _originDx = 0;

  List<AiPttAction> onDown(double dx) {
    phase = AiPttPhase.pressed;
    _originDx = dx;
    return const [];
  }

  /// The widget's 250 ms timer fired while still pressed → begin recording.
  List<AiPttAction> onHoldElapsed() {
    if (phase != AiPttPhase.pressed) return const [];
    phase = AiPttPhase.recording;
    return const [
      AiPttAction.hapticStart,
      AiPttAction.openBubbleListening,
      AiPttAction.startStt,
    ];
  }

  /// A drag ≥80 px to the LEFT of the origin cancels (pressed or recording).
  List<AiPttAction> onMove(double dx) {
    if (phase != AiPttPhase.pressed && phase != AiPttPhase.recording) {
      return const [];
    }
    if (_originDx - dx >= kAiPttCancelDx) {
      final wasRecording = phase == AiPttPhase.recording;
      phase = AiPttPhase.cancelled;
      return [
        AiPttAction.hapticCancel,
        if (wasRecording) AiPttAction.cancelStt,
      ];
    }
    return const [];
  }

  /// Finger lifted. Under the hold threshold → a tap (text mode). While
  /// recording → LOCK it and keep the bubble open (lift-to-lock, the owner's
  /// rule). Already cancelled → nothing.
  List<AiPttAction> onUp(int heldMs) {
    switch (phase) {
      case AiPttPhase.pressed:
        phase = AiPttPhase.idle;
        return heldMs < kAiPttHoldMs
            ? const [AiPttAction.openBubbleComposing]
            : const [];
      case AiPttPhase.recording:
        phase = AiPttPhase.locked; // recording continues, bubble stays open
        return const [];
      case AiPttPhase.cancelled:
        phase = AiPttPhase.idle;
        return const [];
      default:
        return const [];
    }
  }

  /// Stop button, or 2 s silence (VAD) → finalize the transcript.
  List<AiPttAction> onStop() {
    if (phase != AiPttPhase.recording && phase != AiPttPhase.locked) {
      return const [];
    }
    phase = AiPttPhase.idle;
    return const [AiPttAction.finalizeStt];
  }

  void reset() {
    phase = AiPttPhase.idle;
    _originDx = 0;
  }
}
