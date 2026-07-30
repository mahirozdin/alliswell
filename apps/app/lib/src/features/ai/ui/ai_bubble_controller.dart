import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/ulid.dart';
import '../../../i18n/i18n.dart';
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
    if (!state.canSend) return;
    final client = ref.read(aiStreamClientProvider);
    // Resolve the workspace — a FutureProvider is lazy, so .value can be null
    // on a first read even when the session is signed in.
    final workspaces = await ref.read(workspacesProvider.future);
    final workspace = workspaces.isEmpty ? null : workspaces.first;
    if (client == null || workspace == null) {
      state = _machine.offline(state);
      return;
    }

    final requestId = newUlid();
    _cancelled = false;
    final messages = [
      for (final entry in state.history)
        AiChatMessage(role: entry.role, content: entry.text),
      AiChatMessage(role: 'user', content: state.input.trim()),
    ];
    state = _machine.send(state, requestId);

    final request = AiChatRequest(
      workspaceId: workspace.id,
      requestId: requestId,
      messages: messages,
      context: context?.toJson(),
    );
    _sub = client
        .chat(request)
        .listen(
          (event) {
            if (_disposed) return;
            switch (event) {
              case AiTextDelta(:final text):
                state = state.phase == AiBubblePhase.thinking
                    ? _machine.firstToken(state, text)
                    : _machine.appendToken(state, text);
              case AiUsage():
                break;
              case AiStreamDone():
                state = _machine.done(state);
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
    _cancelled = true;
    await _sub?.cancel();
    _sub = null;
    if (!_disposed) state = _machine.done(state);
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
    final firstLine = trimmed.split('\n').first;
    final title = firstLine.length <= 140
        ? firstLine
        : '${firstLine.substring(0, 139).trimRight()}…';
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title,
      'status': 'inbox',
      if (trimmed.length > title.length) 'description': trimmed,
    });
  }
}
