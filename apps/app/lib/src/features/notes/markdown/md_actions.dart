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

/// One thing a writer can do to the text.
class MdAction {
  const MdAction({
    required this.id,
    required this.icon,
    required this.slash,
    required this.apply,
    this.shortcut,
  });

  /// i18n key suffix — `note.action.<id>`.
  final String id;
  final IconData icon;

  /// What typing `/…` matches.
  final String slash;

  /// ⌘/Ctrl shortcut, where one is conventional.
  final SingleActivator? shortcut;

  /// Pure: text + selection in, whole new text + caret out. One assignment
  /// downstream means one undo (D20's principle, applied to every action).
  final MdEdit Function(String text, int start, int end) apply;
}

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

MdEdit _insertBlock(String text, int start, int end, String block) {
  // A block needs its own line; pasting a table into the middle of a sentence
  // produces something no renderer will read as a table.
  final atLineStart = start == 0 || text[start - 1] == '\n';
  final inserted = atLineStart ? block : '\n$block';
  return MdEdit(
    text.replaceRange(start, end, inserted),
    start + inserted.length,
  );
}

const _tableSkeleton = '| Başlık | Başlık |\n| --- | --- |\n|  |  |\n';

/// The actions, in the order the toolbar shows them.
List<MdAction> mdActions() => [
  MdAction(
    id: 'bold',
    icon: Icons.format_bold,
    slash: '/bold',
    shortcut: const SingleActivator(LogicalKeyboardKey.keyB, meta: true),
    apply: (t, s, e) => _wrap(t, s, e, '**', '**'),
  ),
  MdAction(
    id: 'italic',
    icon: Icons.format_italic,
    slash: '/italic',
    shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
    apply: (t, s, e) => _wrap(t, s, e, '*', '*'),
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
    shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
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
    apply: (t, s, e) => _insertBlock(t, s, e, '```\n\n```\n'),
  ),
  MdAction(
    id: 'table',
    icon: Icons.table_chart_outlined,
    slash: '/table',
    apply: (t, s, e) => _insertBlock(t, s, e, _tableSkeleton),
  ),
  MdAction(
    id: 'divider',
    icon: Icons.horizontal_rule,
    slash: '/divider',
    apply: (t, s, e) => _insertBlock(t, s, e, '---\n'),
  ),
];

/// Actions whose slash trigger matches what the writer has typed so far.
///
/// Matching on a PREFIX so `/ta` narrows to `/table`; an exact-match-only menu
/// would mean memorising the command list, which is the invisible surface D19
/// forbids.
List<MdAction> matchSlash(String typed) {
  final needle = typed.toLowerCase();
  if (!needle.startsWith('/')) return const [];
  return [
    for (final action in mdActions())
      if (action.slash.startsWith(needle)) action,
  ];
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
