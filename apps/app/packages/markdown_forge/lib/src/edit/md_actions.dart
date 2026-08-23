/// Every formatting action, once (DESIGN §29 D18/D19, OPH-250).
///
/// D19 says slash commands are "the second path to every toolbar action, never
/// the only one", and D18 asks for a phone toolbar plus desktop shortcuts. Three
/// surfaces, one behaviour — so the actions are declared here and the toolbar,
/// the shortcut map and the slash menu are all built FROM this list.
///
/// Declaring them three times is how a slash command and a toolbar button end
/// up doing subtly different things, and how one of them quietly stops existing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'md_editing.dart';
import '../seams.dart';

/// One thing a writer can do to the text.
class MdAction {
  const MdAction({
    required this.id,
    required this.icon,
    required this.slash,
    required this.apply,
    this.shortcuts = const [],
  });

  /// i18n key suffix — `note.action.<id>`.
  final String id;
  final IconData icon;

  /// What typing `/…` matches.
  final String slash;

  /// The ⌘ *and* Ctrl activators, where a shortcut is conventional.
  final List<SingleActivator> shortcuts;

  /// Pure: text + selection in, whole new text + caret out. One assignment
  /// downstream means one undo (D20's principle, applied to every action).
  final MdEdit Function(String text, int start, int end) apply;
}

/// One shortcut, bound on BOTH desktop conventions.
///
/// `SingleActivator` cannot express "meta OR control", so holding a single
/// activator per action silently meant macOS-only: ⌘B worked, and Ctrl+B did
/// nothing on every Windows, Linux and web build — while this file's own
/// documentation promised "⌘/Ctrl". Returning the pair is what keeps that
/// promise true; `noteFindShortcuts` already does the same thing for ⌘F.
List<SingleActivator> metaOrControl(
  LogicalKeyboardKey key, {
  bool shift = false,
}) => [
  SingleActivator(key, meta: true, shift: shift),
  SingleActivator(key, control: true, shift: shift),
];

/// ⌘K / Ctrl+K — the command palette (D18).
///
/// Not an `MdAction`: the palette is a way to REACH the actions, so putting it
/// in the list would make it findable inside itself.
final List<SingleActivator> mdPaletteShortcuts = metaOrControl(
  LogicalKeyboardKey.keyK,
);

/// Wraps the selection in [left]…[right], or inserts the pair empty.
MdEdit _wrap(String text, int start, int end, String left, String right) {
  final selected = text.substring(start, end);
  final inserted = '$left$selected$right';
  return MdEdit(
    text.replaceRange(start, end, inserted),
    selected.isEmpty ? start + left.length : start + inserted.length,
  );
}

/// Puts [prefix] at the start of every line the selection touches.
MdEdit _prefixLines(String text, int start, int end, String prefix) {
  final lineStart = text.lastIndexOf('\n', start == 0 ? 0 : start - 1) + 1;
  final lineEndRaw = text.indexOf('\n', end);
  final lineEnd = lineEndRaw < 0 ? text.length : lineEndRaw;
  final block = text.substring(lineStart, lineEnd);
  final updated = block
      .split('\n')
      .map((l) => l.startsWith(prefix) ? l : '$prefix$l')
      .join('\n');
  return MdEdit(
    text.replaceRange(lineStart, lineEnd, updated),
    lineStart + updated.length,
  );
}

/// Drops [block] on a line of its own, **without touching the selection**.
///
/// It used to `replaceRange(start, end, …)`, which silently DELETED whatever
/// was selected: select a paragraph, press the code-block button, and the
/// paragraph was gone — replaced by an empty fence (round 19 #3). Every other
/// action wraps or prefixes, so this one read as data loss rather than as a
/// different kind of insert.
///
/// The rule this file now holds: **a formatting action may add, wrap or
/// reorder; it may never destroy the document.** `mdActionsPreserveText` in
/// `note_writing_test.dart` proves it for every entry in [mdActions], so a
/// future action cannot reintroduce the bug.
///
/// A block needs its own line, so the insert lands after the selection's LAST
/// line rather than at the caret — a table in the middle of a sentence is not
/// something any renderer reads as a table.
MdEdit _insertBlock(String text, int start, int end, String block) {
  final lineEndRaw = text.indexOf('\n', end);
  final at = lineEndRaw < 0 ? text.length : lineEndRaw;
  final atLineStart = at == 0 || text[at - 1] == '\n';
  final inserted = atLineStart ? block : '\n$block';
  return MdEdit(text.replaceRange(at, at, inserted), at + inserted.length);
}

/// The fenced-code toggle: wrap the selection, or unwrap it when it is already
/// a fence.
///
/// A toggle rather than a plain insert because that is what the button LOOKS
/// like sitting next to bold and italic — and because "select, press, press
/// again" has to return the document to where it started.
MdEdit _fence(String text, int start, int end) {
  final selected = text.substring(start, end);
  if (selected.isEmpty) {
    // Nothing selected: the old empty fence, caret on the body line.
    return _insertBlock(text, start, end, '```\n\n```\n');
  }
  final unwrapped = _unfence(selected);
  if (unwrapped != null) {
    return MdEdit(
      text.replaceRange(start, end, unwrapped),
      start + unwrapped.length,
    );
  }
  // Trailing newline stripped before wrapping, so the closing fence does not
  // end up with a blank line above it when the writer selected a whole
  // paragraph including its line break.
  final body = selected.endsWith('\n')
      ? selected.substring(0, selected.length - 1)
      : selected;
  final inserted = '```\n$body\n```';
  return MdEdit(
    text.replaceRange(start, end, inserted),
    start + inserted.length,
  );
}

/// The body of [selected] when it is exactly one fenced block, else null.
String? _unfence(String selected) {
  final lines = selected.trimRight().split('\n');
  if (lines.length < 2) return null;
  if (!_fenceLine.hasMatch(lines.first) || !_fenceLine.hasMatch(lines.last)) {
    return null;
  }
  return lines.sublist(1, lines.length - 1).join('\n');
}

final _fenceLine = RegExp(r'^\s{0,3}(```|~~~)\s*[A-Za-z0-9_+-]*\s*$');

/// The table a `/table` insert drops in.
///
/// The header cells were hardcoded Turkish until OPH-274 — a user-facing
/// string that `check:i18n` cannot see, because it never reaches a `Text()`
/// widget: it is typed INTO the user's document, which is the one place a
/// wrong-language string is hardest to notice and most annoying to fix.
String _tableSkeleton(String head) =>
    '| $head | $head |\n| --- | --- |\n|  |  |\n';

/// The actions, in the order the toolbar shows them.
List<MdAction> mdActions({String tableHeader = 'Heading'}) => [
  MdAction(
    id: 'bold',
    icon: Icons.format_bold,
    slash: '/bold',
    shortcuts: metaOrControl(LogicalKeyboardKey.keyB),
    apply: (t, s, e) => _wrap(t, s, e, '**', '**'),
  ),
  MdAction(
    id: 'italic',
    icon: Icons.format_italic,
    slash: '/italic',
    shortcuts: metaOrControl(LogicalKeyboardKey.keyI),
    apply: (t, s, e) => _wrap(t, s, e, '*', '*'),
  ),
  MdAction(
    // OPH-259: markdown's own way to mark text. `==…==` is what the renderer
    // has drawn since OPH-247, and it is theme-safe by construction — a tinted
    // token behind the body ink, never a fixed fill. Text COLOUR stays out of
    // markdown: GFM has no syntax for it (§33 R6, parked with that reason).
    id: 'highlight',
    icon: Icons.format_color_fill,
    slash: '/highlight',
    apply: (t, s, e) => _wrap(t, s, e, '==', '=='),
  ),
  MdAction(
    // GFM's own strikethrough. It had no button while Quill owned the
    // formatting, because Quill had one — removing the rich editor without
    // this would have quietly dropped a format the renderer already draws.
    id: 'strike',
    icon: Icons.strikethrough_s,
    slash: '/strike',
    apply: (t, s, e) => _wrap(t, s, e, '~~', '~~'),
  ),
  MdAction(
    id: 'code',
    icon: Icons.code,
    slash: '/code',
    apply: (t, s, e) => _wrap(t, s, e, '`', '`'),
  ),
  MdAction(
    id: 'link',
    icon: Icons.link,
    slash: '/link',
    // ⌘⇧K, because ⌘K is the palette now. Conventional either way: Slack,
    // Notion and VS Code all reserve the bare ⌘K for a command surface.
    shortcuts: metaOrControl(LogicalKeyboardKey.keyK, shift: true),
    apply: (t, s, e) {
      final selected = t.substring(s, e);
      final inserted = '[$selected]()';
      return MdEdit(
        t.replaceRange(s, e, inserted),
        // Caret inside the parentheses: the label is what you already had, the
        // url is what you came to type.
        s + inserted.length - 1,
      );
    },
  ),
  MdAction(
    id: 'h1',
    icon: Icons.title,
    slash: '/h1',
    apply: (t, s, e) => _prefixLines(t, s, e, '# '),
  ),
  MdAction(
    id: 'h2',
    icon: Icons.text_fields,
    slash: '/h2',
    apply: (t, s, e) => _prefixLines(t, s, e, '## '),
  ),
  MdAction(
    id: 'h3',
    icon: Icons.text_format,
    slash: '/h3',
    apply: (t, s, e) => _prefixLines(t, s, e, '### '),
  ),
  MdAction(
    id: 'bullet',
    icon: Icons.format_list_bulleted,
    slash: '/list',
    apply: (t, s, e) => _prefixLines(t, s, e, '- '),
  ),
  MdAction(
    id: 'numbered',
    icon: Icons.format_list_numbered,
    slash: '/numbered',
    apply: (t, s, e) =>
        MdEdit(renumberOrderedLists(_prefixLines(t, s, e, '1. ').text), e + 3),
  ),
  MdAction(
    id: 'todo',
    icon: Icons.checklist,
    slash: '/todo',
    apply: (t, s, e) => _prefixLines(t, s, e, '- [ ] '),
  ),
  MdAction(
    id: 'quote',
    icon: Icons.format_quote,
    slash: '/quote',
    apply: (t, s, e) => _prefixLines(t, s, e, '> '),
  ),
  MdAction(
    id: 'codeBlock',
    icon: Icons.data_object,
    slash: '/codeblock',
    // WRAPS the selection (and unwraps an existing fence) instead of replacing
    // it — see [_fence]. Every other inline action already behaved this way.
    apply: _fence,
  ),
  MdAction(
    id: 'table',
    icon: Icons.table_chart_outlined,
    slash: '/table',
    apply: (t, s, e) => _insertBlock(t, s, e, _tableSkeleton(tableHeader)),
  ),
  MdAction(
    id: 'divider',
    icon: Icons.horizontal_rule,
    slash: '/divider',
    apply: (t, s, e) => _insertBlock(t, s, e, '---\n'),
  ),
];

/// The one matcher behind both discovery surfaces (D19).
///
/// The slash menu and the command palette must offer the SAME actions; only
/// the way you type differs. A query starting with `/` is a slash token and
/// matches the command by PREFIX — `/ta` narrows to `/table`, because an
/// exact-match-only menu would mean memorising the list, which is the
/// invisible surface D19 forbids. Anything else is a word, and matches the
/// action's label or its command anywhere inside, folded (ADR-0013) so
/// "kalın", "KALIN" and "kalin" all find the same button.
///
/// [label] is injected rather than looked up here so this file stays pure and
/// testable — and because the palette matches what the reader SEES, which is
/// the localized label, not the English id.
///
/// Two matchers is precisely how the palette and the slash menu would come to
/// disagree about what exists — the failure this file's header is written
/// against, one surface further along.
List<MdAction> matchMdActions(
  String query, {
  String Function(MdAction)? label,
  String Function(String) fold = defaultFold,
}) {
  final trimmed = query.trim();
  if (trimmed.startsWith('/')) {
    final needle = trimmed.toLowerCase();
    return [
      for (final action in mdActions())
        if (action.slash.startsWith(needle)) action,
    ];
  }
  final needle = fold(trimmed);
  if (needle.isEmpty) return mdActions();
  return [
    for (final action in mdActions())
      if (fold(label?.call(action) ?? '').contains(needle) ||
          fold(action.slash).contains(needle))
        action,
  ];
}

/// Actions whose slash trigger matches what the writer has typed so far.
List<MdAction> matchSlash(String typed) {
  if (!typed.startsWith('/')) return const [];
  return matchMdActions(typed);
}

/// The slash token immediately before [caret], if the writer is typing one.
///
/// Only at a word boundary: a URL's `https://…` must never open a command menu.
String? slashTokenAt(String text, int caret) {
  if (caret <= 0 || caret > text.length) return null;
  final upto = text.substring(0, caret);
  final slash = upto.lastIndexOf('/');
  if (slash < 0) return null;
  if (slash > 0 && !RegExp(r'[\s\n]').hasMatch(upto[slash - 1])) return null;
  final token = upto.substring(slash);
  if (token.contains(RegExp(r'\s'))) return null;
  return token;
}
