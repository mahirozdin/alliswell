import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/ai_attachments.dart';
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

  test('answer commits both turns and returns to composing (OPH-224)', () {
    var s = m.finalizeTranscript(const AiBubbleState(), 'bugün kaç işim var');
    s = m.answer(s, 'bugün kaç işim var', 'Üç görevin var.');
    expect(s.phase, AiBubblePhase.composing);
    expect(s.input, isEmpty);
    expect(s.history.map((e) => e.role).toList(), ['user', 'assistant']);
    expect(s.history.last.text, 'Üç görevin var.');
  });

  group('OPH-377 attachments', () {
    AiAttachmentRef ref(String id) =>
        AiAttachmentRef(kind: AiAttachmentKind.note, id: id, title: id);

    test('attachPending ignores a duplicate and the sixth item', () {
      var s = const AiBubbleState();
      for (var i = 0; i < kAiAttachPerMessage; i++) {
        s = m.attachPending(s, AiAttachment.loading(ref('N$i')));
      }
      expect(s.pending, hasLength(5));
      s = m.attachPending(s, AiAttachment.loading(ref('N0')));
      s = m.attachPending(s, AiAttachment.loading(ref('N9')));
      expect(s.pending, hasLength(5));
      expect(s.attachLoading, isTrue);
    });

    test('updatePending replaces by ref; a removed chip stays removed', () {
      var s = m.attachPending(
        const AiBubbleState(),
        AiAttachment.loading(ref('N1')),
      );
      s = m.updatePending(s, AiAttachment.ready(ref('N1'), 'metin'));
      expect(s.pending.single.isReady, isTrue);
      expect(s.attachLoading, isFalse);
      s = m.removePending(s, ref('N1'));
      expect(s.pending, isEmpty);
      s = m.updatePending(s, AiAttachment.ready(ref('N1'), 'geç geldi'));
      expect(s.pending, isEmpty);
    });

    test('send moves only READY chips onto the user turn and clears them', () {
      var s = const AiBubbleState().copyWith(input: 'özetle');
      s = m.attachPending(s, AiAttachment.ready(ref('N1'), 'metin'));
      s = m.attachPending(
        s,
        AiAttachment.refused(ref('F1'), AiAttachmentRefusal.notText),
      );
      expect(s.hasReadyPending, isTrue);
      s = m.send(s, 'R');
      expect(s.pending, isEmpty);
      expect(s.history.last.attachments.map((a) => a.ref.id), ['N1']);
    });
  });
}
