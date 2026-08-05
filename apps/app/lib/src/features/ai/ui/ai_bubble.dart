import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheet_rows.dart';
import '../../../widgets/sheets.dart';
import '../../../widgets/status_views.dart';
import '../data/ai_context_builder.dart';
import '../data/ai_live_context.dart';
import '../data/stt.dart';
import 'ai_bubble_controller.dart';
import 'ai_bubble_state.dart';
import 'ai_confirm_card.dart';
import 'ai_text.dart';

/// Opens the AI bubble as a root-navigator modal sheet (DESIGN §24: opaque
/// content surface, glass stays chrome-only). One entry point for the FAB, the
/// share target and the voice path.
Future<void> showAiBubble(BuildContext context, {SharedPayload? shared}) {
  return showAwSheet<void>(
    context,
    showDragHandle: true,
    builder: (_) => AiBubble(shared: shared),
  );
}

class AiBubble extends ConsumerStatefulWidget {
  const AiBubble({super.key, this.shared});
  final SharedPayload? shared;
  @override
  ConsumerState<AiBubble> createState() => _AiBubbleState();
}

class _AiBubbleState extends ConsumerState<AiBubble> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  /// Round 15b: the conversation follows its own tail. `_stick` is true while
  /// the user is AT the bottom — new turns, tokens and the thinking face then
  /// auto-scroll; the moment they scroll up to read, the list stays put until
  /// they return (or send, which always re-sticks).
  final _scroll = ScrollController();
  bool _stick = true;

  void _onScrolled() {
    if (!_scroll.hasClients) return;
    final gap = _scroll.position.maxScrollExtent - _scroll.offset;
    _stick = gap < 96;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A voice session the FAB started (hold-to-talk) is already live on the
      // shared controller — don't reset it back to composing (OPH-224).
      final phase = ref.read(aiBubbleControllerProvider).phase;
      if (phase == AiBubblePhase.listening ||
          phase == AiBubblePhase.reviewing) {
        return;
      }
      ref
          .read(aiBubbleControllerProvider.notifier)
          .openComposing(shared: widget.shared);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When a finalized transcript lands (voice → reviewing), mirror it into the
    // editable field and focus it — nothing is auto-sent (AI9). The text sync
    // fires on any reviewing mismatch (a late final can follow the stop), while
    // focus only grabs on the transition so it never fights the keyboard.
    ref.listen<AiBubbleState>(aiBubbleControllerProvider, (prev, next) {
      final entering =
          next.phase == AiBubblePhase.reviewing &&
          prev?.phase != AiBubblePhase.reviewing;
      if (next.phase == AiBubblePhase.reviewing && _input.text != next.input) {
        _input.text = next.input;
        _input.selection = TextSelection.collapsed(offset: next.input.length);
      }
      if (entering) _inputFocus.requestFocus();
      // The field re-enables when the answer lands — hand the keyboard back.
      final answered =
          next.phase == AiBubblePhase.composing &&
          (prev?.phase == AiBubblePhase.streaming ||
              prev?.phase == AiBubblePhase.thinking);
      if (answered) _inputFocus.requestFocus();
      // Round 15b: anything that grows the conversation pulls the list down —
      // a new turn, a streamed token batch, the thinking face appearing — but
      // only while the user is stuck to the bottom (_stick).
      final grew =
          next.history.length != (prev?.history.length ?? 0) ||
          next.streamed != (prev?.streamed ?? '') ||
          (next.phase == AiBubblePhase.thinking &&
              prev?.phase != AiBubblePhase.thinking);
      if (grew && _stick) _scrollToBottom();
    });

    final state = ref.watch(aiBubbleControllerProvider);
    final controller = ref.read(aiBubbleControllerProvider.notifier);
    final viewport = MediaQuery.sizeOf(context);

    return SizedBox(
      height: (viewport.height * 0.9).clamp(0, viewport.height - 80),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(AwSpace.x4),
                children: [
                  if (widget.shared != null) _sharedBlock(widget.shared!),
                  if (widget.shared != null &&
                      state.history.isEmpty &&
                      state.phase != AiBubblePhase.thinking &&
                      state.phase != AiBubblePhase.streaming)
                    _shareActions(widget.shared!, controller),
                  for (final entry in state.history) _messageRow(entry),
                  if (state.phase == AiBubblePhase.streaming &&
                      state.streamed.isNotEmpty)
                    _assistantBubble(state.streamed),
                  _statusFace(state),
                ],
              ),
            ),
            const Divider(height: 1),
            _composer(state, controller),
          ],
        ),
      ),
    );
  }

  Widget _sharedBlock(SharedPayload shared) => Padding(
    padding: const EdgeInsets.only(bottom: AwSpace.x3),
    child: AwSheetSurface(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ai.bubble.sharedContent'.tr(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Text(shared.url ?? shared.text),
          ],
        ),
      ),
    ),
  );

  Widget _messageRow(AiChatEntry entry) => entry.role == 'user'
      ? _userBubble(entry.text)
      : _assistantBubble(entry.text);

  Widget _userBubble(String text) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      key: const Key('ai-user-message'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2, left: AwSpace.x8),
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      child: Text(text),
    ),
  );

  Widget _assistantBubble(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: const Key('ai-assistant-message'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2, right: AwSpace.x8),
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      child: AiText(
        text,
        onNavigate: (route) {
          Navigator.of(context).pop();
          context.push(route);
        },
      ),
    ),
  );

  Widget _statusFace(AiBubbleState state) {
    switch (state.phase) {
      case AiBubblePhase.listening:
        return Padding(
          key: const Key('ai-listening'),
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.mic, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AwSpace.x2),
                  Text('ai.voice.listening'.tr()),
                ],
              ),
              if (state.partial.isNotEmpty) ...[
                const SizedBox(height: AwSpace.x2),
                Text(
                  state.partial,
                  key: const Key('ai-partial'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ],
          ),
        );
      case AiBubblePhase.thinking:
        return Padding(
          key: const Key('ai-thinking'),
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AwSpace.x3),
              Text('ai.bubble.thinking'.tr()),
            ],
          ),
        );
      case AiBubblePhase.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
          child: AwErrorState(
            message: 'ai.bubble.error'.tr(),
            // Round 15: re-run the FAILED turn (the input was already consumed
            // by the send transition — a plain send() here silently no-oped).
            onRetry: () {
              final controller = ref.read(aiBubbleControllerProvider.notifier);
              controller.retryLast(
                context: buildLiveAiContext(
                  read: ref.read,
                  sharedBlock: ref.read(aiBubbleControllerProvider).sharedBlock,
                ),
              );
            },
          ),
        );
      case AiBubblePhase.offline:
        return Column(
          children: [
            AwEmptyState(
              key: const Key('ai-offline'),
              icon: Icons.cloud_off_outlined,
              title: 'ai.bubble.offlineTitle'.tr(),
              message: 'ai.bubble.offlineBody'.tr(),
            ),
            if (state.input.trim().isNotEmpty)
              _saveToInboxButton(state.input.trim()),
          ],
        );
      case AiBubblePhase.unconfigured:
        return Column(
          children: [
            AwEmptyState(
              key: const Key('ai-unconfigured'),
              icon: Icons.auto_awesome_outlined,
              title: 'ai.bubble.unconfiguredTitle'.tr(),
              message: 'ai.bubble.unconfiguredBody'.tr(),
            ),
            if (state.input.trim().isNotEmpty)
              _saveToInboxButton(state.input.trim()),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// One-tap Inbox capture (OPH-224) — the honest fallback when AI is offline
  /// or unconfigured: nothing said is lost, and it works with zero AI.
  Widget _saveToInboxButton(String text) => Padding(
    padding: const EdgeInsets.only(top: AwSpace.x3),
    child: FilledButton.tonalIcon(
      key: const Key('ai-save-inbox'),
      icon: const Icon(Icons.inbox_outlined),
      label: Text('ai.bubble.saveToInbox'.tr()),
      onPressed: () async {
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        await ref
            .read(aiBubbleControllerProvider.notifier)
            .captureToInbox(text);
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('ai.voice.savedToInbox'.tr())),
        );
      },
    ),
  );

  Widget _composer(AiBubbleState state, AiBubbleController controller) {
    // While recording, the composer is Cancel + Stop (the transcript shows
    // live in the status face above); no text field to fight the mic.
    if (state.phase == AiBubblePhase.listening) {
      return Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Row(
          children: [
            TextButton.icon(
              key: const Key('ai-listen-cancel'),
              onPressed: controller.cancelListening,
              icon: const Icon(Icons.close),
              label: Text('ai.voice.cancel'.tr()),
            ),
            const Spacer(),
            IconButton.filled(
              key: const Key('ai-listen-stop'),
              icon: const Icon(Icons.stop),
              tooltip: 'ai.bubble.stop'.tr(),
              onPressed: controller.stopListening,
            ),
          ],
        ),
      );
    }

    final streaming =
        state.phase == AiBubblePhase.streaming ||
        state.phase == AiBubblePhase.thinking;
    final reviewing = state.phase == AiBubblePhase.reviewing;
    // The mic is offered in text mode when a recognizer exists here; a plain
    // tap on the FAB lands in composing, so the mic is the second way in.
    final micAvailable = ref.watch(sttProvider) != null;
    return Padding(
      padding: const EdgeInsets.all(AwSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('ai-input'),
              controller: _input,
              focusNode: _inputFocus,
              minLines: 1,
              maxLines: 4,
              // Round 15b: while the model is answering, the field is LOCKED —
              // the send-turned-stop button was already saying "one turn at a
              // time"; the field now agrees instead of hoarding the old text.
              enabled: !streaming,
              // Enter sends (hardware keyboards and the mobile action key
              // alike) — the user's report: Enter kept re-submitting the text
              // the field never cleared.
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _onSend(state, controller),
              onChanged: controller.editInput,
              decoration: InputDecoration(
                hintText: 'ai.bubble.hint'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AwSpace.x2),
          if (streaming)
            IconButton.filled(
              key: const Key('ai-stop'),
              icon: const Icon(Icons.stop),
              tooltip: 'ai.bubble.stop'.tr(),
              onPressed: controller.stop,
            )
          else ...[
            if (!reviewing && micAvailable)
              IconButton(
                key: const Key('ai-mic'),
                icon: const Icon(Icons.mic_none_outlined),
                tooltip: 'ai.voice.mic'.tr(),
                onPressed: controller.startListening,
              ),
            IconButton.filled(
              key: const Key('ai-send'),
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'ai.bubble.send'.tr(),
              onPressed: state.canSend
                  ? () => _onSend(state, controller)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  // ── OPH-225: the share target's action chips ────────────────────────────

  /// Four ways to act on shared content + the honest always-works Inbox. "Take
  /// note" and "Save to Inbox" work with zero AI; the AI chips degrade to the
  /// offline capture when no provider is configured.
  Widget _shareActions(SharedPayload shared, AiBubbleController controller) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AwSpace.x3),
        child: Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            ActionChip(
              key: const Key('ai-share-task'),
              avatar: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('ai.share.makeTask'.tr()),
              onPressed: () => _shareMakeTask(shared, controller),
            ),
            ActionChip(
              key: const Key('ai-share-note'),
              avatar: const Icon(Icons.sticky_note_2_outlined, size: 18),
              label: Text('ai.share.takeNote'.tr()),
              onPressed: () => _shareTakeNote(shared, controller),
            ),
            ActionChip(
              key: const Key('ai-share-summarize'),
              avatar: const Icon(Icons.summarize_outlined, size: 18),
              label: Text('ai.share.summarize'.tr()),
              onPressed: () => _shareSummarize(shared, controller),
            ),
            ActionChip(
              key: const Key('ai-share-ask'),
              avatar: const Icon(Icons.help_outline, size: 18),
              label: Text('ai.share.ask'.tr()),
              onPressed: () => _inputFocus.requestFocus(),
            ),
            ActionChip(
              key: const Key('ai-share-inbox'),
              avatar: const Icon(Icons.inbox_outlined, size: 18),
              label: Text('ai.bubble.saveToInbox'.tr()),
              onPressed: () => _shareToInbox(shared, controller),
            ),
          ],
        ),
      );

  String _shareText(SharedPayload shared) => shared.url != null
      ? '${shared.text}\n${shared.url}'.trim()
      : shared.text.trim();

  Future<void> _shareMakeTask(
    SharedPayload shared,
    AiBubbleController controller,
  ) async {
    final route = await controller.extractUtterance(
      _shareText(shared),
      source: 'share',
    );
    if (!mounted) return;
    switch (route) {
      case AiRouteTasks(:final proposal):
        Navigator.of(context).pop();
        await showAiConfirmSheet(context, proposal);
      case AiRouteAnswer(:final text):
        controller.commitShareAnswer(_shareText(shared), text);
      case AiRouteNone():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ai.voice.noIntent'.tr())));
      case AiRouteOffline():
        // No AI here → the honest capture, not a dead end.
        await _shareToInbox(shared, controller);
    }
  }

  Future<void> _shareTakeNote(
    SharedPayload shared,
    AiBubbleController controller,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await controller.shareToNote(shared);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('ai.share.savedNote'.tr())));
  }

  Future<void> _shareToInbox(
    SharedPayload shared,
    AiBubbleController controller,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await controller.captureToInbox(_shareText(shared));
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('ai.voice.savedToInbox'.tr())),
    );
  }

  void _shareSummarize(SharedPayload shared, AiBubbleController controller) {
    controller.editInput('ai.share.summarizePrompt'.tr());
    // Round 15: the shared block rides INSIDE the live bundle — summarize
    // still gets the fenced share, plus the same workspace grounding as any
    // other chat turn.
    controller.send(
      context: buildLiveAiContext(read: ref.read, sharedBlock: shared),
    );
    _input.clear();
  }

  /// Round 15: EVERY typed turn packs the live T0–T2 bundle (AI.md §7 finally
  /// wired — the model used to receive nothing and honestly answered "I can't
  /// see your calendar"), and a share block rides along inside the same
  /// bundle instead of replacing it.
  /// A reviewing (voice/finalized) send runs the intent gate and routes the
  /// outcome; a composing send is a GATED chat turn (round 15): extraction
  /// decides `create_tasks` → confirm card, anything else streams as chat
  /// with the live T0–T2 bundle (a share block rides inside the same bundle).
  Future<void> _onSend(
    AiBubbleState state,
    AiBubbleController controller,
  ) async {
    if (state.phase != AiBubblePhase.reviewing) {
      // Round 15b: the field is the truth at tap time — sync, then clear
      // INSTANTLY. The old flow cleared only after the intent gate answered,
      // which left the sent text sitting in the field for seconds (and an
      // eager Enter re-submitted it).
      final text = _input.text.trim();
      if (text.isEmpty) return;
      controller.editInput(text);
      _input.clear();
      _stick = true;
      _scrollToBottom();
      final proposal = await controller.sendGated(
        context: buildLiveAiContext(
          read: ref.read,
          query: text,
          sharedBlock: state.sharedBlock,
        ),
      );
      if (proposal != null && mounted) {
        Navigator.of(context).pop();
        await showAiConfirmSheet(context, proposal);
      }
      return;
    }
    final route = await controller.submitReview();
    if (!mounted) return;
    switch (route) {
      case AiRouteTasks(:final proposal):
        Navigator.of(context).pop();
        await showAiConfirmSheet(context, proposal);
      case AiRouteAnswer():
      case AiRouteNone():
        _input.clear();
      case AiRouteOffline():
        break; // keep the transcript for the "save to Inbox" affordance
    }
  }
}
