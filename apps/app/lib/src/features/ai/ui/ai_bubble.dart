import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheet_rows.dart';
import '../../../widgets/sheets.dart';
import '../../../widgets/status_views.dart';
import '../data/ai_context_builder.dart';
import 'ai_bubble_controller.dart';
import 'ai_bubble_state.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(aiBubbleControllerProvider.notifier)
          .openComposing(shared: widget.shared);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.all(AwSpace.x4),
                children: [
                  if (widget.shared != null) _sharedBlock(widget.shared!),
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
            onRetry: () => ref.read(aiBubbleControllerProvider.notifier).send(),
          ),
        );
      case AiBubblePhase.offline:
        return AwEmptyState(
          key: const Key('ai-offline'),
          icon: Icons.cloud_off_outlined,
          title: 'ai.bubble.offlineTitle'.tr(),
          message: 'ai.bubble.offlineBody'.tr(),
        );
      case AiBubblePhase.unconfigured:
        return AwEmptyState(
          key: const Key('ai-unconfigured'),
          icon: Icons.auto_awesome_outlined,
          title: 'ai.bubble.unconfiguredTitle'.tr(),
          message: 'ai.bubble.unconfiguredBody'.tr(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _composer(AiBubbleState state, AiBubbleController controller) {
    final streaming =
        state.phase == AiBubblePhase.streaming ||
        state.phase == AiBubblePhase.thinking;
    return Padding(
      padding: const EdgeInsets.all(AwSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('ai-input'),
              controller: _input,
              minLines: 1,
              maxLines: 4,
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
          else
            IconButton.filled(
              key: const Key('ai-send'),
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'ai.bubble.send'.tr(),
              onPressed: state.canSend
                  ? () {
                      controller.send();
                      _input.clear();
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}
