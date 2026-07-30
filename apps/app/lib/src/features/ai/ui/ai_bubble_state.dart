import '../data/ai_context_builder.dart';

/// The bubble's states (OPH-221, DESIGN §24 AI4). Every state has a face; none
/// lies. The machine is PURE — the controller owns the impure edges (timers,
/// stream subscription, drift writes) and delegates transitions here.
enum AiBubblePhase {
  composing, // text field + mic toggle (the default; also unconfigured hint below)
  listening, // recording, live partial transcript
  reviewing, // a finalized transcript, editable, before send
  thinking, // sent, awaiting the first token
  streaming, // tokens arriving, live Stop
  error,
  offline, // no network / send failed — offer "save to Inbox"
  unconfigured, // AI is enabled but no connection — capture works, output is Inbox
}

class AiChatEntry {
  const AiChatEntry({required this.role, required this.text, this.context});
  final String role; // user | assistant
  final String text;
  final AiContextBundle? context;
}

class AiBubbleState {
  const AiBubbleState({
    this.phase = AiBubblePhase.composing,
    this.input = '',
    this.partial = '',
    this.streamed = '',
    this.requestId,
    this.errorCode,
    this.history = const [],
    this.sharedBlock,
  });

  final AiBubblePhase phase;
  final String input;
  final String partial;
  final String streamed;
  final String? requestId;
  final String? errorCode;
  final List<AiChatEntry> history;
  final SharedPayload? sharedBlock;

  bool get canSend => input.trim().isNotEmpty || partial.trim().isNotEmpty;

  AiBubbleState copyWith({
    AiBubblePhase? phase,
    String? input,
    String? partial,
    String? streamed,
    String? requestId,
    String? errorCode,
    List<AiChatEntry>? history,
    SharedPayload? sharedBlock,
    bool clearRequestId = false,
    bool clearError = false,
    bool clearShared = false,
  }) {
    return AiBubbleState(
      phase: phase ?? this.phase,
      input: input ?? this.input,
      partial: partial ?? this.partial,
      streamed: streamed ?? this.streamed,
      requestId: clearRequestId ? null : (requestId ?? this.requestId),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      history: history ?? this.history,
      sharedBlock: clearShared ? null : (sharedBlock ?? this.sharedBlock),
    );
  }
}

/// Pure transitions. The controller calls these; nothing here does I/O.
class AiBubbleMachine {
  const AiBubbleMachine();

  AiBubbleState openComposing(AiBubbleState s, {SharedPayload? shared}) =>
      s.copyWith(
        phase: AiBubblePhase.composing,
        sharedBlock: shared,
        clearError: true,
      );

  AiBubbleState openUnconfigured(AiBubbleState s) =>
      s.copyWith(phase: AiBubblePhase.unconfigured, clearError: true);

  AiBubbleState editInput(AiBubbleState s, String text) =>
      s.copyWith(input: text);

  AiBubbleState startListening(AiBubbleState s) =>
      s.copyWith(phase: AiBubblePhase.listening, partial: '', clearError: true);

  AiBubbleState partialTranscript(AiBubbleState s, String text) =>
      s.copyWith(partial: text);

  /// The transcript is always editable before anything is sent (AI9): finalize
  /// moves it into the input, focused, in the reviewing phase.
  AiBubbleState finalizeTranscript(AiBubbleState s, String text) =>
      s.copyWith(phase: AiBubblePhase.reviewing, input: text, partial: '');

  AiBubbleState send(AiBubbleState s, String requestId) {
    final text = s.input.trim();
    return s.copyWith(
      phase: AiBubblePhase.thinking,
      requestId: requestId,
      streamed: '',
      input: '',
      history: [
        ...s.history,
        AiChatEntry(role: 'user', text: text),
      ],
      clearError: true,
    );
  }

  /// OPH-224 — an `answer`-intent extraction comes back complete in one round
  /// trip (no streaming): commit both the user turn and the reply to history
  /// and return to composing. `none` reuses this with a hint reply.
  AiBubbleState answer(AiBubbleState s, String userText, String answerText) =>
      s.copyWith(
        phase: AiBubblePhase.composing,
        input: '',
        history: [
          ...s.history,
          AiChatEntry(role: 'user', text: userText),
          AiChatEntry(role: 'assistant', text: answerText),
        ],
        clearError: true,
      );

  AiBubbleState firstToken(AiBubbleState s, String text) =>
      s.copyWith(phase: AiBubblePhase.streaming, streamed: text);

  AiBubbleState appendToken(AiBubbleState s, String text) =>
      s.copyWith(streamed: s.streamed + text);

  /// Stream finished. The assistant turn is committed to history; a cancel
  /// keeps whatever partial text arrived (marked by the controller).
  AiBubbleState done(AiBubbleState s) => s.copyWith(
    phase: AiBubblePhase.composing,
    history: s.streamed.isEmpty
        ? s.history
        : [...s.history, AiChatEntry(role: 'assistant', text: s.streamed)],
    streamed: '',
    clearRequestId: true,
  );

  AiBubbleState fail(AiBubbleState s, String code) => s.copyWith(
    phase: AiBubblePhase.error,
    errorCode: code,
    clearRequestId: true,
  );

  AiBubbleState offline(AiBubbleState s) =>
      s.copyWith(phase: AiBubblePhase.offline, clearRequestId: true);
}
