import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/ulid.dart';
import '../../../i18n/i18n.dart';
import '../../notes/providers.dart';
import '../../projects/providers.dart';
import '../../tasks/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/ai_context_builder.dart';
import '../data/ai_models.dart';
import '../data/ai_stream_client.dart';
import '../data/stt.dart';
import '../providers.dart';
import 'ai_bubble_state.dart';

/// Where an extracted utterance routes (OPH-224). The bubble UI acts on it:
/// tasks → confirm card, answer → chat stream, none → a hint, offline → the
/// transcript is preserved for one-tap Inbox capture.
sealed class AiVoiceRoute {
  const AiVoiceRoute();
}

class AiRouteTasks extends AiVoiceRoute {
  const AiRouteTasks(this.proposal);
  final AiProposal proposal;
}

class AiRouteAnswer extends AiVoiceRoute {
  const AiRouteAnswer(this.text);
  final String text;
}

class AiRouteNone extends AiVoiceRoute {
  const AiRouteNone();
}

class AiRouteOffline extends AiVoiceRoute {
  const AiRouteOffline(this.transcript);
  final String transcript;
}

/// Owns the bubble's impure edges (the stream subscription, the request id)
/// and delegates every transition to the pure [AiBubbleMachine] (OPH-221).
final aiBubbleControllerProvider =
    NotifierProvider<AiBubbleController, AiBubbleState>(AiBubbleController.new);

class AiBubbleController extends Notifier<AiBubbleState> {
  static const _machine = AiBubbleMachine();
  StreamSubscription<AiStreamEvent>? _sub;
  SttController? _stt;
  bool _cancelled = false;
  bool _disposed = false;

  /// Round 15b: send/sendGated/retryLast await network BEFORE the machine
  /// commits the turn (so an offline failure keeps the input for the Inbox
  /// capture) — which left a re-entrancy window where a second Enter re-sent
  /// the SAME message. One flag closes it; the phase guard below covers the
  /// rest of the stream's lifetime.
  bool _busySending = false;

  bool get _sendBlocked =>
      _busySending ||
      state.phase == AiBubblePhase.thinking ||
      state.phase == AiBubblePhase.streaming;

  @override
  AiBubbleState build() {
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _stt?.cancel();
    });
    return const AiBubbleState();
  }

  SharedPayload? _pendingShared;

  void openComposing({SharedPayload? shared}) {
    _pendingShared = shared;
    _applyStatus(ref.read(aiStatusProvider).value, shared: shared);
    // The status is async — re-evaluate once it resolves (a fresh launch reads
    // null first). Only while the user has not started a conversation.
    ref.listen(aiStatusProvider, (_, next) {
      if (state.history.isEmpty &&
          (state.phase == AiBubblePhase.composing ||
              state.phase == AiBubblePhase.unconfigured)) {
        _applyStatus(next.value, shared: _pendingShared);
      }
    });
  }

  void _applyStatus(AiStatus? status, {SharedPayload? shared}) {
    if (_disposed) return;
    if (status != null && status.enabled && !status.configured) {
      state = _machine.openUnconfigured(state).copyWith(sharedBlock: shared);
    } else {
      state = _machine.openComposing(state, shared: shared);
    }
  }

  void editInput(String text) => state = _machine.editInput(state, text);

  /// Sends the current input as a chat turn, streaming the answer. Context is
  /// packed by the caller (kept minimal here so the controller stays testable).
  Future<void> send({AiContextBundle? context}) async {
    if (_sendBlocked || !state.canSend) return;
    _busySending = true;
    try {
      final prepared = await _prepare();
      if (prepared == null) return; // offline face; the input is preserved
      final requestId = newUlid();
      _cancelled = false;
      state = _machine.send(state, requestId);
      _stream(prepared, requestId, context);
    } finally {
      _busySending = false;
    }
  }

  /// Round 15 — the typed path gets the OPH-224 intent gate too, chat flavor:
  /// extraction runs FIRST (fast class, source `bubble`); `create_tasks` comes
  /// back as a proposal for the widget to open the confirm card, anything else
  /// falls through to the STREAMED chat turn with the packed context — the
  /// extract's own answer is deliberately discarded (chat has the history and
  /// the T0–T2 bundle; the gate only decides). The user turn + thinking face
  /// commit BEFORE the gate so the tap answers instantly, and a gate failure
  /// of any kind degrades to plain chat, never to a dead end.
  Future<AiProposal?> sendGated({AiContextBundle? context}) async {
    if (_sendBlocked || !state.canSend) return null;
    _busySending = true;
    try {
      final text = state.input.trim();
      final prepared = await _prepare();
      if (prepared == null) {
        return null; // offline face; the input is preserved
      }
      final requestId = newUlid();
      _cancelled = false;
      state = _machine.send(state, requestId);

      AiVoiceRoute route;
      try {
        route = await extractUtterance(text, source: 'bubble');
      } on Object catch (_) {
        route = const AiRouteNone();
      }
      if (_disposed || _cancelled) return null;
      if (route case AiRouteTasks(:final proposal)) {
        // The confirm card takes over; the bubble returns to composing.
        state = _machine.done(state);
        return proposal;
      }
      _stream(prepared, requestId, context);
      return null;
    } finally {
      _busySending = false;
    }
  }

  /// The error face's retry: the failed turn is already the last history
  /// entry (the send transition committed it), so re-stream from history —
  /// with empty input the old `send()` was a silent no-op and the retry
  /// button lied (round 15).
  Future<void> retryLast({AiContextBundle? context}) async {
    if (state.history.isEmpty || state.history.last.role != 'user') {
      return send(context: context);
    }
    if (_sendBlocked) return;
    _busySending = true;
    try {
      final prepared = await _prepare();
      if (prepared == null) return;
      final requestId = newUlid();
      _cancelled = false;
      state = _machine.retry(state, requestId);
      _stream(prepared, requestId, context);
    } finally {
      _busySending = false;
    }
  }

  /// Resolves the transport + workspace, or shows the offline face (keeping
  /// the input so "save to Inbox" still has the text). A FutureProvider is
  /// lazy, so `.value` can be null on a first read even when signed in.
  Future<({AiStreamClient client, String workspaceId})?> _prepare() async {
    final client = ref.read(aiStreamClientProvider);
    final workspaces = await ref.read(workspacesProvider.future);
    final workspace = workspaces.isEmpty ? null : workspaces.first;
    if (client == null || workspace == null) {
      state = _machine.offline(state);
      return null;
    }
    return (client: client, workspaceId: workspace.id);
  }

  /// One streaming turn: the message list is HISTORY as-is (the send/retry
  /// transition already committed the user turn).
  void _stream(
    ({AiStreamClient client, String workspaceId}) prepared,
    String requestId,
    AiContextBundle? context,
  ) {
    final messages = [
      for (final entry in state.history)
        AiChatMessage(role: entry.role, content: entry.text),
    ];
    final request = AiChatRequest(
      workspaceId: prepared.workspaceId,
      requestId: requestId,
      messages: messages,
      context: context?.toJson(),
    );
    _sub = prepared.client
        .chat(request)
        .listen(
          (event) {
            // A straggler delivered while stop() tears the transport down
            // must not repaint a face the user already dismissed (15b).
            if (_disposed || _cancelled) return;
            switch (event) {
              case AiTextDelta(:final text):
                state = state.phase == AiBubblePhase.thinking
                    ? _machine.firstToken(state, text)
                    : _machine.appendToken(state, text);
              case AiUsage():
                break;
              case AiStreamDone():
                // A server `error` event is followed by the stream's normal
                // end (round 15): the trailing Done must not clobber the
                // error face the user needs to see and retry from.
                if (state.phase != AiBubblePhase.error) {
                  state = _machine.done(state);
                }
              case AiStreamFailure(:final code):
                if (!_cancelled) state = _machine.fail(state, code);
            }
          },
          onError: (_) {
            if (!_disposed) state = _machine.fail(state, 'AI_UPSTREAM_ERROR');
          },
        );
  }

  /// Stop — the live cancel. The stream ends as `done{cancelled}`; whatever
  /// text arrived stays.
  Future<void> stop() async {
    // Round 15b: the face answers the TAP, not the teardown — awaiting the
    // subscription cancel first left the bubble visibly "streaming" until the
    // transport finished dying (the locked-input test caught it). Stragglers
    // that were already in flight are voided by the _cancelled guard in
    // _stream's listener.
    _cancelled = true;
    final sub = _sub;
    _sub = null;
    if (!_disposed) state = _machine.done(state);
    await sub?.cancel();
  }

  void reset() {
    _sub?.cancel();
    _sub = null;
    state = const AiBubbleState();
  }

  // ── Voice: the STT session (OPH-223/224) ──────────────────────────────
  // The controller owns the impure edges (the recognizer, its callbacks); the
  // pure [AiBubbleMachine] owns every transition. `sttProvider` is nullable —
  // null means voice is unavailable here (web / no recognizer), so we fall
  // back to text mode honestly (AI10: the gesture is never the only way).

  /// Begins recording. Sets the listening phase optimistically (so a sheet
  /// opened by the FAB renders the right face before the engine warms up),
  /// then initializes; a denied permission or missing engine drops to text.
  Future<void> startListening() async {
    final stt = ref.read(sttProvider);
    if (stt == null) {
      state = _machine.openComposing(state);
      return;
    }
    _stt = stt;
    state = _machine.startListening(state);
    final init = await stt.initialize();
    if (_disposed) return;
    if (!init.available) {
      // No mic permission / no recognizer → honest text mode, not a dead end.
      _stt = null;
      state = _machine.openComposing(state);
      return;
    }
    await stt.start(
      localeId: _sttLocaleId(),
      onResult: (text, isFinal) {
        if (_disposed) return;
        if (isFinal) {
          _finalizeTranscript(text);
        } else {
          state = _machine.partialTranscript(state, text);
        }
      },
    );
  }

  /// The Stop button (or the plugin's VAD). The final result arrives through
  /// `onResult(_, true)` → [_finalizeTranscript]; a partial-only session keeps
  /// whatever text we have so nothing said is lost.
  Future<void> stopListening() async {
    await _stt?.stop();
    if (_disposed) return;
    // Guard the rare case where stop yields no final frame: promote the live
    // partial so the user still gets an editable transcript.
    if (state.phase == AiBubblePhase.listening) {
      _finalizeTranscript(state.partial);
    }
  }

  /// The swipe-left cancel (driven from the FAB) — discard, back to composing.
  Future<void> cancelListening() async {
    await _stt?.cancel();
    _stt = null;
    if (!_disposed) state = _machine.openComposing(state);
  }

  void _finalizeTranscript(String text) {
    _stt = null;
    state = _machine.finalizeTranscript(state, text.trim());
  }

  String _sttLocaleId() =>
      AwI18n.instance.locale.languageCode == 'tr' ? 'tr_TR' : 'en_US';

  /// OPH-224 — submit a reviewed transcript through the intent gate and apply
  /// the non-navigational outcomes here (answer/none/offline mutate the bubble;
  /// `create_tasks` is returned so the widget can close the sheet and open the
  /// confirm card, which needs a BuildContext). Nothing is auto-sent (AI9): the
  /// user always taps send on an editable transcript first.
  Future<AiVoiceRoute> submitReview({String source = 'voice'}) async {
    final userText = state.input.trim();
    if (userText.isEmpty) return const AiRouteNone();
    final route = await extractUtterance(userText, source: source);
    if (_disposed) return route;
    switch (route) {
      case AiRouteTasks():
        break; // handled by the widget (pop + confirm card)
      case AiRouteAnswer(:final text):
        state = _machine.answer(state, userText, text);
      case AiRouteNone():
        state = _machine.answer(state, userText, 'ai.voice.noIntent'.tr());
      case AiRouteOffline():
        // Keep the transcript in the input so the offline face can offer the
        // one-tap Inbox capture.
        state = _machine.offline(state);
    }
    return route;
  }

  /// OPH-225 — a share's "make task" chip got an `answer` back instead: show
  /// it inline (both turns), same as the voice answer route.
  void commitShareAnswer(String userText, String answerText) {
    if (!_disposed) state = _machine.answer(state, userText, answerText);
  }

  /// OPH-224 — the intent gate in one round trip: a finalized transcript goes
  /// to `/ai/extract` on the fast class; `intent` decides. `create_tasks` →
  /// the tasks come back on the same response; `answer` → the bubble streams
  /// a chat reply; `none` → a hint. Offline / unconfigured → the transcript is
  /// preserved for one-tap Inbox capture ("capture works with zero AI").
  Future<AiVoiceRoute> extractUtterance(
    String text, {
    required String source,
  }) async {
    final workspaces = await ref.read(workspacesProvider.future);
    final status = ref.read(aiStatusProvider).value;
    if (workspaces.isEmpty || status == null || !status.configured) {
      return AiRouteOffline(text);
    }
    final projectNames =
        (ref.read(projectsControllerProvider).value ?? const [])
            .map((p) => p.name)
            .toList();
    try {
      final proposal = await ref
          .read(aiApiProvider)
          .extract(
            workspaces.first.id,
            text: text,
            source: source,
            defaultTaskTime: ref.read(defaultTaskTimeProvider),
            projectNames: projectNames,
          );
      return switch (proposal.intent) {
        'create_tasks' when proposal.tasks.isNotEmpty => AiRouteTasks(proposal),
        'answer' => AiRouteAnswer(proposal.answer ?? ''),
        _ => const AiRouteNone(),
      };
    } on ApiException {
      // A network failure (or an honest extraction error) preserves the text.
      return AiRouteOffline(text);
    }
  }

  /// One-tap Inbox capture (§12.6 GTD semantics) — works with zero AI. The
  /// first line (clipped) is the title; a longer transcript spills to the body.
  Future<void> captureToInbox(String text) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    final trimmed = text.trim();
    final title = _clipTitle(trimmed);
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title,
      'status': 'inbox',
      if (trimmed.length > title.length) 'description': trimmed,
    });
  }

  /// OPH-225 — "take note" on a share: a note with zero AI (the honest path
  /// that always works). First line (clipped) is the title, the whole text is
  /// the body.
  Future<void> shareToNote(SharedPayload shared) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    final body = shared.url != null
        ? '${shared.text}\n${shared.url}'.trim()
        : shared.text.trim();
    await ref.read(noteStoreProvider).create(workspaces.first.id, {
      'title': _clipTitle(body),
      'contentMarkdown': body,
    });
  }

  String _clipTitle(String text) {
    final firstLine = text.split('\n').first;
    return firstLine.length <= 140
        ? firstLine
        : '${firstLine.substring(0, 139).trimRight()}…';
  }
}
