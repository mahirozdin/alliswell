import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/ui/ai_bubble_state.dart';

/// OPH-221 — the bubble machine is a pure transition table.
void main() {
  const m = AiBubbleMachine();

  test('send moves to thinking, commits the user turn, clears input', () {
    var s = const AiBubbleState().copyWith(input: 'merhaba');
    s = m.send(s, 'REQ1');
    expect(s.phase, AiBubblePhase.thinking);
    expect(s.requestId, 'REQ1');
    expect(s.input, '');
    expect(s.history.last.role, 'user');
    expect(s.history.last.text, 'merhaba');
  });

  test('firstToken → streaming; appendToken accumulates', () {
    var s = m.send(const AiBubbleState().copyWith(input: 'x'), 'R');
    s = m.firstToken(s, 'Mer');
    expect(s.phase, AiBubblePhase.streaming);
    s = m.appendToken(s, 'haba');
    expect(s.streamed, 'Merhaba');
  });

  test('done commits the assistant turn and clears the request id', () {
    var s = m.send(const AiBubbleState().copyWith(input: 'x'), 'R');
    s = m.firstToken(s, 'cevap');
    s = m.done(s);
    expect(s.phase, AiBubblePhase.composing);
    expect(s.requestId, isNull);
    expect(s.history.last.role, 'assistant');
    expect(s.history.last.text, 'cevap');
  });

  test('done with no streamed text adds nothing to history', () {
    var s = m.send(const AiBubbleState().copyWith(input: 'x'), 'R');
    final before = s.history.length;
    s = m.done(s);
    expect(s.history.length, before);
  });

  test('fail → error state, request cleared', () {
    var s = m.send(const AiBubbleState().copyWith(input: 'x'), 'R');
    s = m.fail(s, 'AI_UPSTREAM_ERROR');
    expect(s.phase, AiBubblePhase.error);
    expect(s.errorCode, 'AI_UPSTREAM_ERROR');
    expect(s.requestId, isNull);
  });

  test('a transcript is editable before send (finalize → reviewing)', () {
    var s = m.startListening(const AiBubbleState());
    s = m.partialTranscript(s, 'yarım');
    expect(s.phase, AiBubblePhase.listening);
    s = m.finalizeTranscript(s, 'Ahmet projesine fatura ekle');
    expect(s.phase, AiBubblePhase.reviewing);
    expect(s.input, 'Ahmet projesine fatura ekle');
    expect(s.canSend, isTrue);
  });

  test('offline transition clears the request', () {
    var s = m.send(const AiBubbleState().copyWith(input: 'x'), 'R');
    s = m.offline(s);
    expect(s.phase, AiBubblePhase.offline);
    expect(s.requestId, isNull);
  });
}
