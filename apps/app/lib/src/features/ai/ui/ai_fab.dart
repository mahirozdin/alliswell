import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../providers.dart';
import 'ai_bubble.dart';
import 'ai_bubble_controller.dart';
import 'ai_ptt_machine.dart';

/// The press-to-talk AI FAB (OPH-223, DESIGN §24 AI1): bottom-LEFT, distinct
/// from the bottom-right create FAB. Hold ≥250 ms to talk; lift locks and keeps
/// the bubble open; swipe left to cancel; a plain tap opens the bubble in
/// text + mic mode (the tap path is never the only way — AI2/AI10).
///
/// The pure [AiPttMachine] decides; this widget owns the 250 ms timer and the
/// side effects (haptics, opening the bubble). Real recording is wired in the
/// bubble via the STT seam; this FAB is present whenever AI is enabled.
class AiFab extends ConsumerStatefulWidget {
  const AiFab({super.key});
  @override
  ConsumerState<AiFab> createState() => _AiFabState();
}

class _AiFabState extends ConsumerState<AiFab> {
  final _machine = AiPttMachine();
  Timer? _holdTimer;
  DateTime? _downAt;

  /// True between a pointer's lift and the end of the event that carried it.
  /// The machine already answered that touch (a tap opens the bubble from
  /// `onUp`); the FAB's own `onPressed` fires for the SAME touch a moment
  /// later in the same dispatch and must not open a second bubble.
  bool _pointerAnswered = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _run(List<AiPttAction> actions) {
    for (final action in actions) {
      switch (action) {
        case AiPttAction.hapticStart:
          HapticFeedback.mediumImpact();
        case AiPttAction.hapticCancel:
          HapticFeedback.heavyImpact();
        case AiPttAction.openBubbleComposing:
          showAiBubble(context);
        case AiPttAction.openBubbleListening:
          showAiBubble(context);
        case AiPttAction.startStt:
          // Shared provider: the bubble the line above opened reads the same
          // controller, so it renders the live session (OPH-224).
          ref.read(aiBubbleControllerProvider.notifier).startListening();
        case AiPttAction.finalizeStt:
          ref.read(aiBubbleControllerProvider.notifier).stopListening();
        case AiPttAction.cancelStt:
          ref.read(aiBubbleControllerProvider.notifier).cancelListening();
      }
    }
  }

  void _onDown(PointerDownEvent e) {
    _downAt = DateTime.now();
    _run(_machine.onDown(e.position.dx));
    _holdTimer?.cancel();
    _holdTimer = Timer(
      const Duration(milliseconds: kAiPttHoldMs),
      () => _run(_machine.onHoldElapsed()),
    );
  }

  void _onMove(PointerMoveEvent e) => _run(_machine.onMove(e.position.dx));

  void _onUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    final heldMs = _downAt == null
        ? 0
        : DateTime.now().difference(_downAt!).inMilliseconds;
    _run(_machine.onUp(heldMs));
    _pointerAnswered = true;
    // Cleared once this event has been dispatched: the tap recogniser fires
    // `onPressed` synchronously inside it, so anything arriving later — a
    // screen reader's activation, Enter on a focused button — is new.
    scheduleMicrotask(() => _pointerAnswered = false);
  }

  /// The path with no pointer behind it (OPH-359, UI-AUDIT #55): a screen
  /// reader's double-tap, Flutter web's semantic click, Enter or Space on a
  /// focused button. All of them arrive as `onPressed` and nothing else, and
  /// it used to be `() {}` — so with accessibility on, the button did
  /// nothing at all. It opens the bubble the way a plain tap does.
  void _onActivated() {
    if (_pointerAnswered) return;
    showAiBubble(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      // ONE node, named, with the action on it (UI-AUDIT #64): wrapping the
      // FAB in a labelled Semantics used to leave the FAB's own unnamed
      // button beside it — two stops for a screen reader, one of them silent.
      child: Semantics(
        button: true,
        label: 'ai.voice.fabLabel'.tr(),
        hint: 'ai.voice.fabHint'.tr(),
        excludeSemantics: true,
        onTap: _onActivated,
        child: FloatingActionButton(
          key: const Key('ai-fab'),
          heroTag: 'ai-fab',
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          onPressed: _onActivated,
          child: const Icon(Icons.mic_none_outlined),
        ),
      ),
    );
  }
}

/// Whether the AI FAB should show — AI enabled on the server (configured or
/// not; an unconfigured bubble still captures to Inbox, AI4).
bool aiFabVisible(WidgetRef ref) =>
    ref.watch(aiStatusProvider).value?.enabled ?? false;
