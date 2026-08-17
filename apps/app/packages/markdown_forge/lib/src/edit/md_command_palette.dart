/// The command palette (DESIGN §29 D18, OPH-250).
///
/// D18 asks for "keyboard shortcuts and a command palette" on desktop. This is
/// not a second command list — it is a fourth VIEW of `mdActions()`, beside the
/// toolbar, the shortcut map and the slash menu, and it goes through the same
/// `matchMdActions` the slash menu uses.
///
/// What it adds over the slash menu is keyboard navigation and searching by
/// NAME. The slash menu is tap-only and inline, which is right while you are
/// typing prose and wrong when you have taken your hands off the mouse and
/// cannot remember whether the command is `/list` or `/bullet`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'md_actions.dart';
import '../seams.dart';

/// One row, fixed — so arrow-key navigation scrolls by arithmetic instead of
/// measuring a tile that may not be laid out yet.
const double kMdPaletteRowHeight = 48;

/// How many rows are visible before the list scrolls.
const int kMdPaletteVisibleRows = 7;

/// The localized name the palette matches and shows.
String mdActionLabel(BuildContext context, MdAction action) =>
    context.mdStrings.action(action.id);

/// Opens the palette. Resolves to the chosen action, or null if dismissed.
Future<MdAction?> showMdCommandPalette(BuildContext context) =>
    showModalBottomSheet<MdAction>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const MdCommandPalette(),
    );

class MdCommandPalette extends StatefulWidget {
  const MdCommandPalette({super.key});

  @override
  State<MdCommandPalette> createState() => _MdCommandPaletteState();
}

class _MdCommandPaletteState extends State<MdCommandPalette> {
  // The key handler hangs on the FIELD's own node, not on an ancestor Focus:
  // `DefaultTextEditingShortcuts` is installed near the root, so an ancestor
  // handler would run only after the text field had already acted on the key.
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final ScrollController _scroll = ScrollController();
  String _query = '';
  int _selected = 0;

  List<MdAction> get _matches => matchMdActions(
    _query,
    label: (action) => mdActionLabel(context, action),
    fold: context.mdStrings.fold,
  );

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final matches = _matches;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, matches.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, matches.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (matches.isNotEmpty) {
        Navigator.of(
          context,
        ).pop(matches[_selected.clamp(0, matches.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves the highlight, wrapping at both ends.
  ///
  /// Wrapping is deliberate: thirteen actions in a seven-row window, and a
  /// palette that dead-ends at the bottom sends you back to the mouse.
  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    _revealSelected();
  }

  void _revealSelected() {
    if (!_scroll.hasClients) return;
    final top = _selected * kMdPaletteRowHeight;
    final bottom = top + kMdPaletteRowHeight;
    final viewport = _scroll.position.viewportDimension;
    double? target;
    if (top < _scroll.offset) {
      target = top;
    } else if (bottom > _scroll.offset + viewport) {
      target = bottom - viewport;
    }
    if (target == null) return;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches = _matches;
    final selected = matches.isEmpty
        ? 0
        : _selected.clamp(0, matches.length - 1);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(MdSpace.x4),
            child: TextField(
              key: const Key('md-palette-field'),
              focusNode: _focus,
              autofocus: true,
              onChanged: (value) => setState(() {
                _query = value;
                // Back to the top: the old highlight belonged to a list that
                // no longer exists.
                _selected = 0;
              }),
              decoration: InputDecoration(
                hintText: context.mdStrings.searchCommands,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MdRadius.m),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: MdSpace.x4,
                right: MdSpace.x4,
                bottom: MdSpace.x5,
              ),
              child: Text(
                context.mdStrings.noCommands,
                key: const Key('md-palette-empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: kMdPaletteRowHeight * kMdPaletteVisibleRows,
              ),
              child: ListView.builder(
                key: const Key('md-palette-list'),
                controller: _scroll,
                shrinkWrap: true,
                itemExtent: kMdPaletteRowHeight,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final action = matches[index];
                  return ListTile(
                    key: Key('md-palette-${action.id}'),
                    dense: true,
                    selected: index == selected,
                    // The highlight is a TILE colour, not a text colour: the
                    // default `selectedColor` repaints label and icon in
                    // `primary`, which is a contrast pair nothing has measured
                    // (§11, and OPH-247's lesson about inventing a background).
                    selectedColor: scheme.onSurface,
                    selectedTileColor: scheme.surfaceContainerHighest,
                    leading: Icon(action.icon, size: 18),
                    title: Text(mdActionLabel(context, action)),
                    trailing: Text(
                      action.slash,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => Navigator.of(context).pop(action),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
