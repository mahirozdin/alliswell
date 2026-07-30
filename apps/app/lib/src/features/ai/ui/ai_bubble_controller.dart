import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ulid.dart';
import '../../workspaces/workspaces.dart';
import '../data/ai_context_builder.dart';
import '../data/ai_models.dart';
import '../data/ai_stream_client.dart';
import '../providers.dart';
import 'ai_bubble_state.dart';

/// Owns the bubble's impure edges (the stream subscription, the request id)
/// and delegates every transition to the pure [AiBubbleMachine] (OPH-221).
final aiBubbleControllerProvider =
    NotifierProvider<AiBubbleController, AiBubbleState>(AiBubbleController.new);

class AiBubbleController extends Notifier<AiBubbleState> {
  static const _machine = AiBubbleMachine();
  StreamSubscription<AiStreamEvent>? _sub;
  bool _cancelled = false;
  bool _disposed = false;

  @override
  AiBubbleState build() {
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
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
}
