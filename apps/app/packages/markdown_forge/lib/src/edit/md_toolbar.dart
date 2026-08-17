/// The writer's controls (DESIGN §29 D18/D19/D22/D23, OPH-250).
///
/// One action list, three ways in — a scrolling toolbar above the keyboard on a
/// phone, ⌘/Ctrl shortcuts on desktop, and slash commands everywhere. They are
/// built from `mdActions()` rather than declared separately, which is what
/// keeps a slash command from quietly diverging from the button beside it.
library;

import 'package:flutter/material.dart';

import 'md_actions.dart';
import 'md_editing.dart';
import '../seams.dart';

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

/// The editor's toolbar (D18, revised by OPH-274).
///
/// This is the bar that used to be `QuillSimpleToolbar`, in the same place —
/// above the document, on every screen width. D18 originally put it above the
/// KEYBOARD on a phone and offered nothing but shortcuts on desktop, which
/// made sense while the rich editor owned the top of the screen. With the rich
/// editor gone that would have left a wide window with no visible formatting
/// controls at all, so there is now ONE bar and it is always there. It
/// scrolls horizontally rather than wrapping: a second row would push the
/// document down on exactly the screens that have the least of it.
class MdEditorToolbar extends StatelessWidget {
  const MdEditorToolbar({
    super.key,
    required this.controller,
    this.onApplied,
    this.trailing,
  });

  final TextEditingController controller;
  final VoidCallback? onApplied;

  /// Controls that are not text formatting — the media inserts. They sit
  /// OUTSIDE the scrolling list so they never scroll out of reach.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('md-toolbar'),
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: context.mdTheme.hairline),
          bottom: BorderSide(color: context.mdTheme.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MdSpace.x1),
              children: [
                for (final action in mdActions())
                  IconButton(
                    key: Key('md-action-${action.id}'),
                    tooltip: context.mdStrings.action(action.id),
                    icon: Icon(action.icon, size: 20),
                    onPressed: () {
                      applyMdAction(controller, action);
                      onApplied?.call();
                    },
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            VerticalDivider(
              width: 1,
              indent: MdSpace.x2,
              endIndent: MdSpace.x2,
              color: context.mdTheme.hairline,
            ),
            trailing!,
          ],
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
      margin: const EdgeInsets.symmetric(horizontal: MdSpace.x4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(MdRadius.m)),
        border: Border.all(color: context.mdTheme.hairline),
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
                title: Text(context.mdStrings.action(action.id)),
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
        horizontal: MdSpace.x5,
        vertical: MdSpace.x1,
      ),
      child: Text(
        context.mdStrings.counts(counts.words, counts.characters),
        key: const Key('md-count-strip'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
