/// The writer's controls (DESIGN §29 D18/D19/D22/D23, OPH-250).
///
/// One action list, three ways in — a scrolling toolbar above the keyboard on a
/// phone, ⌘/Ctrl shortcuts on desktop, and slash commands everywhere. They are
/// built from `mdActions()` rather than declared separately, which is what
/// keeps a slash command from quietly diverging from the button beside it.
library;

import 'package:flutter/material.dart';

import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../markdown/md_actions.dart';
import '../../markdown/md_editing.dart';

/// Applies [action] to [controller] in ONE assignment, so one undo reverts it.
void applyMdAction(TextEditingController controller, MdAction action) {
  final selection = controller.selection;
  final start = selection.start < 0 ? controller.text.length : selection.start;
  final end = selection.end < 0 ? controller.text.length : selection.end;
  final edit = action.apply(controller.text, start, end);
  controller.value = TextEditingValue(
    text: edit.text,
    selection: TextSelection.collapsed(offset: edit.selection),
  );
}

/// The scrolling toolbar D18 asks for on a phone.
class MdToolbar extends StatelessWidget {
  const MdToolbar({super.key, required this.controller, this.onApplied});

  final TextEditingController controller;
  final VoidCallback? onApplied;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('md-toolbar'),
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: context.awTokens.hairline)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AwSpace.x1),
        children: [
          for (final action in mdActions())
            IconButton(
              key: Key('md-action-${action.id}'),
              tooltip: 'note.action.${action.id}'.tr(),
              icon: Icon(action.icon, size: 20),
              onPressed: () {
                applyMdAction(controller, action);
                onApplied?.call();
              },
            ),
        ],
      ),
    );
  }
}

/// The slash menu (D19) — the same actions, filtered by what is being typed.
class MdSlashMenu extends StatelessWidget {
  const MdSlashMenu({super.key, required this.matches, required this.onPick});

  final List<MdAction> matches;
  final void Function(MdAction) onPick;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    // A Material of its own: `ListTile` paints its fill and its ink on the
    // nearest Material ancestor, so a coloured Container around it would hide
    // both — Flutter asserts on exactly this.
    return Container(
      key: const Key('md-slash-menu'),
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        border: Border.all(color: context.awTokens.hairline),
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final action in matches)
              ListTile(
                key: Key('md-slash-${action.id}'),
                dense: true,
                leading: Icon(action.icon, size: 18),
                title: Text('note.action.${action.id}'.tr()),
                trailing: Text(
                  action.slash,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () => onPick(action),
              ),
          ],
        ),
      ),
    );
  }
}

/// Word and character count (D22): "always available, never in the way".
class MdCountStrip extends StatelessWidget {
  const MdCountStrip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final counts = countText(text);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x5,
        vertical: AwSpace.x1,
      ),
      child: Text(
        'note.counts'.tr(
          args: {
            'words': '${counts.words}',
            'characters': '${counts.characters}',
          },
        ),
        key: const Key('md-count-strip'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
