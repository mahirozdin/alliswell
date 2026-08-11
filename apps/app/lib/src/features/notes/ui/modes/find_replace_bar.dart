/// Find & replace over the markdown source (DESIGN §29 D15, OPH-249).
///
/// D15 exists because the rich editor's search button shipped **disabled**
/// (`showSearchButton: false`) — a control that existed and did nothing, which
/// §22 calls out by name. That flag is on now; Source mode had no search at
/// all, so it gets this.
///
/// **One undo returns the document.** Replace-all writes the whole text in a
/// single controller assignment rather than looping edits, so Flutter's undo
/// stack sees one change — and D20's "smart paste without one-step undo is
/// hostile" is the same principle a rule earlier.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';

/// Every match of [needle] in [haystack], as start offsets.
///
/// Case-insensitive, because a reader looking for "Kurulum" means "kurulum"
/// too. Not fold-insensitive: replacing `ı` when somebody typed `i` would
/// rewrite text they did not mean, and search-to-READ (ADR-0013) and
/// search-to-REWRITE are different promises.
List<int> findMatches(String haystack, String needle) {
  if (needle.isEmpty) return const [];
  final hay = haystack.toLowerCase();
  final pin = needle.toLowerCase();
  final hits = <int>[];
  var from = 0;
  while (true) {
    final at = hay.indexOf(pin, from);
    if (at < 0) break;
    hits.add(at);
    from = at + pin.length;
  }
  return hits;
}

/// Replaces every match in one string operation.
String replaceAllMatches(String haystack, String needle, String replacement) {
  final hits = findMatches(haystack, needle);
  if (hits.isEmpty) return haystack;
  final out = StringBuffer();
  var cursor = 0;
  for (final at in hits) {
    out
      ..write(haystack.substring(cursor, at))
      ..write(replacement);
    cursor = at + needle.length;
  }
  out.write(haystack.substring(cursor));
  return out.toString();
}

class FindReplaceBar extends StatefulWidget {
  const FindReplaceBar({
    super.key,
    required this.target,
    required this.onClose,
    this.showReplace = false,
  });

  /// The text being searched — and, for replace, rewritten.
  final TextEditingController target;
  final VoidCallback onClose;
  final bool showReplace;

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  List<int> _matches = const [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _findFocus.requestFocus();
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _search(String needle) {
    setState(() {
      _matches = findMatches(widget.target.text, needle);
      _index = 0;
    });
    _select();
  }

  /// Selecting the hit is the whole point of "next": a counter that moves
  /// while the document does not is a counter nobody trusts.
  void _select() {
    if (_matches.isEmpty) return;
    final at = _matches[_index];
    widget.target.selection = TextSelection(
      baseOffset: at,
      extentOffset: at + _find.text.length,
    );
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _index = (_index + delta) % _matches.length);
    _select();
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    // ONE assignment, so ONE undo takes the document back.
    widget.target.text = replaceAllMatches(
      widget.target.text,
      _find.text,
      _replace.text,
    );
    _search(_find.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counter = _matches.isEmpty
        ? (_find.text.isEmpty ? '' : 'note.noMatches'.tr())
        : 'note.matchCount'.tr(
            args: {'index': '${_index + 1}', 'total': '${_matches.length}'},
          );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x3,
        vertical: AwSpace.x2,
      ),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('note-find-field'),
              controller: _find,
              focusNode: _findFocus,
              onChanged: _search,
              onSubmitted: (_) => _step(1),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'note.find'.tr(),
              ),
            ),
          ),
          if (widget.showReplace) ...[
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: TextField(
                key: const Key('note-replace-field'),
                controller: _replace,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'note.replace'.tr(),
                ),
              ),
            ),
            const SizedBox(width: AwSpace.x2),
            TextButton(
              key: const Key('note-replace-all'),
              onPressed: _matches.isEmpty ? null : _replaceAll,
              child: Text('note.replaceAll'.tr()),
            ),
          ],
          const SizedBox(width: AwSpace.x2),
          Text(
            counter,
            key: const Key('note-find-counter'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            key: const Key('note-find-prev'),
            tooltip: 'common.previous'.tr(),
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _matches.isEmpty ? null : () => _step(-1),
          ),
          IconButton(
            key: const Key('note-find-next'),
            tooltip: 'common.next'.tr(),
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _matches.isEmpty ? null : () => _step(1),
          ),
          IconButton(
            key: const Key('note-find-close'),
            tooltip: 'common.close'.tr(),
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

/// ⌘F / Ctrl+F and ⌘⌥F / Ctrl+H (D15).
Map<ShortcutActivator, VoidCallback> noteFindShortcuts({
  required VoidCallback onFind,
  required VoidCallback onReplace,
}) => {
  const SingleActivator(LogicalKeyboardKey.keyF, control: true): onFind,
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onFind,
  const SingleActivator(LogicalKeyboardKey.keyH, control: true): onReplace,
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true, alt: true):
      onReplace,
};
