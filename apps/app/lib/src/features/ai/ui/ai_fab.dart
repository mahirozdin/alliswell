import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../providers.dart';
import 'ai_bubble.dart';
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
        case AiPttAction.finalizeStt:
        case AiPttAction.cancelStt:
          // The bubble drives the STT session (OPH-224); the FAB only opens it.
          break;
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      child: Semantics(
        button: true,
        label: 'ai.voice.fabLabel'.tr(),
        hint: 'ai.voice.fabHint'.tr(),
        child: FloatingActionButton(
          key: const Key('ai-fab'),
          heroTag: 'ai-fab',
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          // A plain tap (no hold) is handled by the machine via onUp; onPressed
          // is a no-op so the button still reports as pressable to a11y tools.
          onPressed: () {},
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
