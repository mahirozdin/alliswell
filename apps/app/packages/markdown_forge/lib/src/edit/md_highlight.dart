/// Editing markdown and SEEING it (DESIGN §29 D23/D24, OPH-274).
///
/// The rich editor is gone (ADR-0033), and a plain monospace field would have
/// been a real loss: Quill's whole job was showing you that a heading is a
/// heading while you type it. This is that feedback, done the Obsidian/Typora
/// way — headings are large in the field, bold is bold, and the syntax marks
/// fade back unless the caret is on their line.
///
/// ## The constraint that shapes everything here
///
/// This is a genuine `TextField`, and a `TextEditingController` must return a
/// span tree containing **exactly** the characters of `text`. Drop a `**` and
/// every caret offset, selection, undo entry and IME composition after it
/// points at the wrong character. So "hide the syntax" is not available at any
/// price: markers can only be RESTYLED, never removed. What "shown only on the
/// current line" means in a text field is therefore *quiet* elsewhere, not
/// absent — and quiet is done with `onSurfaceVariant`, a role that still
/// clears 4.5:1 in both themes (Rule 11 has no carve-out for decoration).
///
/// ## Cost
///
/// `buildTextSpan` runs on every rebuild over the WHOLE document, and note
/// bodies go to a megabyte. The scan is one pass per line, and its result is
/// cached against the text itself — typing a character re-scans, moving the
/// caret does not.
library;

import 'package:flutter/material.dart';
import '../seams.dart';

/// What a run of source text IS, independent of how it is painted.
enum MdTokenKind {
  plain,

  /// Syntax: `#`, `**`, `- `, `> `, the ``` fence, a link's `](url)`.
  marker,
  heading1,
  heading2,
  heading3,
  headingSmall,
  bold,
  italic,
  code,
  codeBlock,
  strike,
  mark,
  link,
  quote,
}

/// One contiguous run of the source, and the line it sits on.
@immutable
class MdToken {
  const MdToken(this.start, this.end, this.kind, this.line);

  final int start;
  final int end;
  final MdTokenKind kind;
  final int line;
}

const _headingStyles = [
  MdTokenKind.heading1,
  MdTokenKind.heading2,
  MdTokenKind.heading3,
  MdTokenKind.headingSmall,
  MdTokenKind.headingSmall,
  MdTokenKind.headingSmall,
];

final _fenceRe = RegExp(r'^\s{0,3}(```|~~~)');
final _headingRe = RegExp(r'^(\s{0,3})(#{1,6})(\s+)');
final _quoteRe = RegExp(r'^(\s{0,3}>\s?)');
final _listRe = RegExp(r'^(\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)');
final _ruleRe = RegExp(r'^\s{0,3}([-*_])\s*(?:\1\s*){2,}$');

/// Inline constructs, longest-and-most-specific first so `**` never loses to
/// `*` and an image never parses as a link.
final _inlineRe = RegExp(
  r'(?<img>!\[[^\]\n]*\]\([^)\n]*\))'
  r'|(?<link>\[[^\]\n]*\]\([^)\n]*\))'
  r'|(?<code>`[^`\n]+`)'
  r'|(?<bold>\*\*[^\n]+?\*\*|__[^\n]+?__)'
  r'|(?<strike>~~[^\n]+?~~)'
  r'|(?<mark>==[^\n]+?==)'
  r'|(?<italic>\*[^*\n]+?\*|_[^_\n]+?_)',
);

/// Splits markdown source into styled runs.
///
/// Deliberately line-based and deliberately not the real parser
/// (`md_parse.dart`). That one builds a document tree with source positions
/// for the reading view and the outline; this one has to answer "what colour
/// is character 40 000" fast enough to run between two keystrokes, and it is
/// allowed to be approximate — a mis-tinted character is a cosmetic miss,
/// where a mis-parsed document is a wrong page.
List<MdToken> scanMarkdown(String text) {
  final tokens = <MdToken>[];
  if (text.isEmpty) return tokens;

  var offset = 0;
  var line = 0;
  var inFence = false;

  void emit(int start, int end, MdTokenKind kind) {
    if (end > start) tokens.add(MdToken(start, end, kind, line));
  }

  /// Inline pass over one range of a line.
  void inlines(int start, int end, MdTokenKind base) {
    var cursor = start;
    for (final m in _inlineRe.allMatches(text.substring(start, end))) {
      final mStart = start + m.start;
      final mEnd = start + m.end;
      if (mStart < cursor) continue; // overlapped by a previous match
      emit(cursor, mStart, base);

      void wrapped(int openLen, int closeLen, MdTokenKind inner) {
        emit(mStart, mStart + openLen, MdTokenKind.marker);
        emit(mStart + openLen, mEnd - closeLen, inner);
        emit(mEnd - closeLen, mEnd, MdTokenKind.marker);
      }

      if (m.namedGroup('img') != null || m.namedGroup('link') != null) {
        // `![label](url)` / `[label](url)`: the label is the document's words,
        // the target is plumbing. Colour the first, mute the second.
        final openLen = m.namedGroup('img') != null ? 2 : 1;
        final tail = text.indexOf('](', mStart + openLen);
        if (tail == -1 || tail >= mEnd) {
          emit(mStart, mEnd, MdTokenKind.marker);
        } else {
          emit(mStart, mStart + openLen, MdTokenKind.marker);
          emit(mStart + openLen, tail, MdTokenKind.link);
          emit(tail, mEnd, MdTokenKind.marker);
        }
      } else if (m.namedGroup('code') != null) {
        wrapped(1, 1, MdTokenKind.code);
      } else if (m.namedGroup('bold') != null) {
        wrapped(2, 2, MdTokenKind.bold);
      } else if (m.namedGroup('strike') != null) {
        wrapped(2, 2, MdTokenKind.strike);
      } else if (m.namedGroup('mark') != null) {
        wrapped(2, 2, MdTokenKind.mark);
      } else {
        wrapped(1, 1, MdTokenKind.italic);
      }
      cursor = mEnd;
    }
    emit(cursor, end, base);
  }

  while (offset <= text.length) {
    final br = text.indexOf('\n', offset);
    final lineEnd = br == -1 ? text.length : br;
    final content = text.substring(offset, lineEnd);

    if (_fenceRe.hasMatch(content)) {
      inFence = !inFence;
      emit(offset, lineEnd, MdTokenKind.marker);
    } else if (inFence) {
      emit(offset, lineEnd, MdTokenKind.codeBlock);
    } else if (_ruleRe.hasMatch(content)) {
      emit(offset, lineEnd, MdTokenKind.marker);
    } else {
      final heading = _headingRe.firstMatch(content);
      final quote = _quoteRe.firstMatch(content);
      final list = _listRe.firstMatch(content);
      if (heading != null) {
        final markerEnd = offset + heading.end;
        emit(offset, markerEnd, MdTokenKind.marker);
        inlines(
          markerEnd,
          lineEnd,
          _headingStyles[heading.group(2)!.length - 1],
        );
      } else if (quote != null) {
        emit(offset, offset + quote.end, MdTokenKind.marker);
        inlines(offset + quote.end, lineEnd, MdTokenKind.quote);
      } else if (list != null) {
        emit(offset, offset + list.end, MdTokenKind.marker);
        inlines(offset + list.end, lineEnd, MdTokenKind.plain);
      } else {
        inlines(offset, lineEnd, MdTokenKind.plain);
      }
    }

    if (br == -1) break;
    emit(lineEnd, lineEnd + 1, MdTokenKind.plain); // the newline itself
    offset = lineEnd + 1;
    line += 1;
  }
  return tokens;
}

/// How much of the document's formatting the SOURCE field paints (round 19 #4).
///
/// Round 19 asked the question this enum answers: "I bolded a selection and the
/// editor bolded it too — but that is the editing surface, not the reading
/// one." Both readings are legitimate (Obsidian paints, a code editor does
/// not), so it stops being a hardcoded taste and becomes a choice.
///
/// The old `bool liveSyntax` could express only the two ends of this and was
/// wired to nothing — a switch with no handle, always on. [markersOnly] is the
/// middle the report is actually asking for, and the new default.
enum MdSyntaxStyling {
  /// No colour at all. The raw text, the way a plain editor shows it.
  plain,

  /// **Colour only.** `#`, `**`, `>` and a link's target step back in
  /// `onSurfaceVariant`; a heading takes the accent ink. Nothing changes
  /// WEIGHT, SIZE, SLANT, BACKGROUND or DECORATION — those belong to Reading
  /// mode, which is the whole point of having two modes.
  markersOnly,

  /// The Obsidian/Typora treatment: headings are large, bold is bold,
  /// highlight is highlighted, right there in the field.
  live,
}

/// The Source-mode text controller: live syntax, plus focus mode.
///
/// A subclass rather than a second controller: D3 keeps ONE controller alive
/// for the document's whole life, so both of these have to be properties of
/// that controller rather than a swap.
class MdSourceController extends TextEditingController {
  MdSourceController({super.text});

  bool _focusMode = false;
  bool get focusMode => _focusMode;
  set focusMode(bool value) {
    if (value == _focusMode) return;
    _focusMode = value;
    notifyListeners();
  }

  MdSyntaxStyling _styling = MdSyntaxStyling.markersOnly;

  /// What the field paints. The host owns this (AllisWell persists it as a
  /// setting); the package only obeys.
  MdSyntaxStyling get styling => _styling;
  set styling(MdSyntaxStyling value) {
    if (value == _styling) return;
    _styling = value;
    notifyListeners();
  }

  String? _scannedText;
  List<MdToken>? _tokens;

  /// The scan, reused until the text itself changes. Moving the caret through
  /// a long document must not re-tokenise it.
  List<MdToken> get tokens {
    if (_scannedText != text || _tokens == null) {
      _scannedText = text;
      _tokens = scanMarkdown(text);
    }
    return _tokens!;
  }

  /// The paragraph around [offset] — bounded by blank lines, the way markdown
  /// itself decides where a paragraph ends.
  ({int start, int end}) paragraphAt(int offset) {
    final caret = offset.clamp(0, text.length);
    var start = 0;
    var end = text.length;
    final breakRe = RegExp(r'\n[ \t]*\n');
    for (final match in breakRe.allMatches(text)) {
      if (match.end <= caret) {
        start = match.end;
      } else {
        end = match.start;
        break;
      }
    }
    return (start: start, end: end);
  }

  /// Which line the caret is on, or -1 when there is no caret.
  int _caretLine() {
    final caret = selection.baseOffset;
    if (caret < 0) return -1;
    var line = 0;
    for (var i = 0; i < caret && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line += 1;
    }
    return line;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty || (_styling == MdSyntaxStyling.plain && !_focusMode)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final base = style ?? const TextStyle();
    final palette = _MdSourcePalette.of(context, base);
    final caretLine = _caretLine();

    // Focus mode dims, it does not hide: everything outside the paragraph
    // holding the caret fades, and nothing leaves the layout, because removing
    // text reflows the page and reflow is what makes a focus mode unusable.
    final focus = _focusMode
        ? paragraphAt(selection.baseOffset < 0 ? 0 : selection.baseOffset)
        : null;

    TextStyle dim(TextStyle s, int start) {
      if (focus == null || (start >= focus.start && start < focus.end)) {
        return s;
      }
      final color = s.color ?? palette.body;
      return s.copyWith(color: color.withValues(alpha: color.a * 0.35));
    }

    if (_styling == MdSyntaxStyling.plain) {
      // Focus mode alone — the three-span tree this file used to build.
      return TextSpan(
        style: base,
        children: [
          if (focus!.start > 0)
            TextSpan(text: text.substring(0, focus.start), style: dim(base, 0)),
          TextSpan(text: text.substring(focus.start, focus.end), style: base),
          if (focus.end < text.length)
            TextSpan(
              text: text.substring(focus.end),
              style: dim(base, focus.end),
            ),
        ],
      );
    }

    return TextSpan(
      style: base,
      children: [
        for (final token in tokens)
          TextSpan(
            text: text.substring(token.start, token.end),
            style: dim(
              palette.styleFor(token.kind, token.line == caretLine, _styling),
              token.start,
            ),
          ),
      ],
    );
  }
}

/// The colours and weights live syntax paints with, resolved once per build.
///
/// Every value comes from `AwTokens` or the `ColorScheme` (Rule 11). The
/// markers use `onSurfaceVariant` rather than a hand-rolled alpha: it is a
/// role that stays >= 4.5:1 in both themes, so the syntax reads as quiet
/// without becoming a contrast failure the way a 35%-alpha grey would.
@immutable
class _MdSourcePalette {
  const _MdSourcePalette({
    required this.body,
    required this.marker,
    required this.accent,
    required this.link,
    required this.codeInk,
    required this.markTint,
    required this.base,
  });

  factory _MdSourcePalette.of(BuildContext context, TextStyle base) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.mdTheme;
    return _MdSourcePalette(
      body: base.color ?? scheme.onSurface,
      marker: scheme.onSurfaceVariant,
      accent: scheme.onSurface,
      link: tokens.link,
      codeInk: scheme.onSurfaceVariant,
      markTint: tokens.warning.withValues(alpha: 0.22),
      base: base,
    );
  }

  final Color body;
  final Color marker;
  final Color accent;
  final Color link;
  final Color codeInk;
  final Color markTint;
  final TextStyle base;

  /// [onCaretLine] is what makes the syntax step forward as you reach it:
  /// markers take full body ink on the line you are editing and fall back to
  /// the muted role everywhere else.
  ///
  /// [styling] decides how far the painting goes. Under
  /// [MdSyntaxStyling.markersOnly] this method may return a `color` and
  /// **nothing else** — no weight, size, slant, background or decoration.
  /// `md_highlight_test.dart` asserts exactly that over every token kind, so
  /// "the editor stopped being a preview" cannot regress one case at a time.
  TextStyle styleFor(
    MdTokenKind kind,
    bool onCaretLine,
    MdSyntaxStyling styling,
  ) {
    final quiet = styling == MdSyntaxStyling.markersOnly;
    switch (kind) {
      case MdTokenKind.plain:
        return base;
      case MdTokenKind.marker:
        return base.copyWith(color: onCaretLine ? body : marker);
      case MdTokenKind.heading1:
        if (quiet) return base.copyWith(color: accent);
        return base.copyWith(
          fontSize: (base.fontSize ?? 14) * 1.5,
          fontWeight: FontWeight.w700,
          color: accent,
        );
      case MdTokenKind.heading2:
        if (quiet) return base.copyWith(color: accent);
        return base.copyWith(
          fontSize: (base.fontSize ?? 14) * 1.3,
          fontWeight: FontWeight.w700,
          color: accent,
        );
      case MdTokenKind.heading3:
        if (quiet) return base.copyWith(color: accent);
        return base.copyWith(
          fontSize: (base.fontSize ?? 14) * 1.15,
          fontWeight: FontWeight.w600,
          color: accent,
        );
      case MdTokenKind.headingSmall:
        if (quiet) return base.copyWith(color: accent);
        return base.copyWith(fontWeight: FontWeight.w600, color: accent);
      // The four the round-19 report is about. Under `markersOnly` the `**`,
      // `*`, `~~` and `==` stay VISIBLE (they are markers) but the text they
      // wrap is not restyled — that is Reading mode's job.
      case MdTokenKind.bold:
        if (quiet) return base;
        return base.copyWith(fontWeight: FontWeight.w700);
      case MdTokenKind.italic:
        if (quiet) return base;
        return base.copyWith(fontStyle: FontStyle.italic);
      case MdTokenKind.strike:
        if (quiet) return base;
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case MdTokenKind.mark:
        if (quiet) return base;
        return base.copyWith(backgroundColor: markTint);
      case MdTokenKind.code:
      case MdTokenKind.codeBlock:
        return base.copyWith(color: codeInk);
      case MdTokenKind.link:
        if (quiet) return base.copyWith(color: link);
        return base.copyWith(color: link, decoration: TextDecoration.underline);
      case MdTokenKind.quote:
        if (quiet) return base.copyWith(color: marker);
        return base.copyWith(fontStyle: FontStyle.italic, color: marker);
    }
  }
}
