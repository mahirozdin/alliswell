import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/ui/ai_ptt_machine.dart';

/// OPH-223 — the press-to-talk gesture machine is a pure transition table
/// (DESIGN §24 AI2). The widget owns the timers; this owns the rules.
void main() {
  test('tap under the hold threshold opens the text/mic composer', () {
    final m = AiPttMachine();
    m.onDown(0);
    final actions = m.onUp(120); // released before 250 ms
    expect(actions, contains(AiPttAction.openBubbleComposing));
    expect(m.phase, AiPttPhase.idle);
  });

  test('hold ≥250 ms begins recording with a haptic', () {
    final m = AiPttMachine();
    m.onDown(0);
    final actions = m.onHoldElapsed();
    expect(
      actions,
      containsAll([AiPttAction.hapticStart, AiPttAction.startStt]),
    );
    expect(m.phase, AiPttPhase.recording);
  });

  test(
    'lifting while recording LOCKS it (bubble stays open) — the owner rule',
    () {
      final m = AiPttMachine();
      m.onDown(0);
      m.onHoldElapsed();
      final actions = m.onUp(900);
      expect(actions, isEmpty); // nothing torn down
      expect(m.phase, AiPttPhase.locked);
    },
  );

  test('a left swipe ≥80 px cancels a recording with a haptic', () {
    final m = AiPttMachine();
    m.onDown(200);
    m.onHoldElapsed();
    final actions = m.onMove(200 - kAiPttCancelDx); // exactly at the threshold
    expect(
      actions,
      containsAll([AiPttAction.hapticCancel, AiPttAction.cancelStt]),
    );
    expect(m.phase, AiPttPhase.cancelled);
  });

  test('a small move does not cancel', () {
    final m = AiPttMachine();
    m.onDown(200);
    m.onHoldElapsed();
    expect(m.onMove(180), isEmpty); // only 20 px
    expect(m.phase, AiPttPhase.recording);
  });

  test('stop (or VAD) finalizes from recording or locked', () {
    final recording = AiPttMachine()
      ..onDown(0)
      ..onHoldElapsed();
    expect(recording.onStop(), contains(AiPttAction.finalizeStt));

    final locked = AiPttMachine()
      ..onDown(0)
      ..onHoldElapsed()
      ..onUp(900);
    expect(locked.phase, AiPttPhase.locked);
    expect(locked.onStop(), contains(AiPttAction.finalizeStt));
    expect(locked.phase, AiPttPhase.idle);
  });

  test('a cancelled gesture ignores the subsequent lift', () {
    final m = AiPttMachine();
    m.onDown(200);
    m.onHoldElapsed();
    m.onMove(0); // cancel
    expect(m.onUp(900), isEmpty);
    expect(m.phase, AiPttPhase.idle);
  });
}
