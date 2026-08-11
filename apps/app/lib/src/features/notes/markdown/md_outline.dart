/// The heading tree, and the anchors it answers to (DESIGN §29 D13/D16,
/// OPH-249).
///
/// Both come from the same place — a document's headings — so they live
/// together. Splitting them is how an outline and an anchor end up disagreeing
/// about what a section is called.
///
/// ## Why the slug is ours
///
/// `markdown`'s own `HeaderWithIdSyntax` generates `id="trke-balk"` for
/// "Türkçe Başlık": it DROPS ş/ı/ç rather than folding them, so
/// `[git](#türkçe-başlık)` could never resolve. OPH-247 measured that and
/// pinned it with a test so this task could not trip over it.
///
/// The fix is the one ADR-0013 already reached for search: folding is
/// **app-owned**. `foldSearchText` maps ı→i, ş→s, ç→c and the rest, and
/// GitHub's rules do the remainder — lowercase, drop punctuation, spaces to
/// hyphens.
library;

import '../../../core/fold.dart';
import 'md_parse.dart';

/// One heading, and where it lives.
class MdHeading {
  const MdHeading({
    required this.level,
    required this.text,
    required this.slug,
    required this.blockIndex,
    required this.startLine,
  });

  /// 1–6.
  final int level;
  final String text;

  /// The anchor `[…](#slug)` must use.
  final String slug;

  /// Index into [MdDocument.blocks] — what a jump scrolls to.
  final int blockIndex;

  /// Source line, for the editor side of a jump.
  final int startLine;
}

/// A heading plus the headings nested under it.
class MdOutlineNode {
  MdOutlineNode(this.heading) : children = [];

  final MdHeading heading;
  final List<MdOutlineNode> children;
}

/// A document's headings, flat and in document order.
List<MdHeading> outlineHeadings(MdDocument doc) {
  final seen = <String, int>{};
  final headings = <MdHeading>[];

  for (var i = 0; i < doc.blocks.length; i++) {
    final block = doc.blocks[i];
    final tag = block.tag;
    if (tag == null || !RegExp(r'^h[1-6]$').hasMatch(tag)) continue;

    final text = block.node.textContent.trim();
    final base = markdownSlug(text);
    // GitHub's own de-duplication: the second "Kurulum" is `kurulum-1`. Without
    // it two sections share an anchor and one of them is unreachable.
    final count = seen.update(base, (n) => n + 1, ifAbsent: () => 0);
    headings.add(
      MdHeading(
        level: int.parse(tag.substring(1)),
        text: text,
        slug: count == 0 ? base : '$base-$count',
        blockIndex: i,
        startLine: block.startLine,
      ),
    );
  }
  return headings;
}

/// Nests [headings] by level.
///
/// A document that starts at `###` or jumps from `#` to `####` is not
/// malformed, it is normal — so the nesting attaches each heading to the
/// nearest shallower one rather than assuming a tidy 1-2-3.
List<MdOutlineNode> buildOutline(List<MdHeading> headings) {
  final roots = <MdOutlineNode>[];
  final stack = <MdOutlineNode>[];

  for (final heading in headings) {
    final node = MdOutlineNode(heading);
    while (stack.isNotEmpty && stack.last.heading.level >= heading.level) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.children.add(node);
    }
    stack.add(node);
  }
  return roots;
}

/// GitHub's heading slug, with Turkish folded rather than deleted (D16).
String markdownSlug(String heading) {
  // Fold FIRST: `foldSearchText` lowercases and maps ı→i, ş→s, ç→c… Doing it
  // after stripping punctuation would already have lost the letters.
  final folded = foldSearchText(heading);
  return folded
      // GitHub keeps letters, digits, spaces and hyphens; everything else goes.
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), '-');
}

/// The block a `#anchor` points at, or null when nothing matches.
///
/// Compared on the SLUG, not the text: `#türkçe-başlık` and `#TÜRKÇE-BAŞLIK`
/// name the same section, and a reader who typed the heading by hand should
/// still land on it.
MdHeading? headingForAnchor(List<MdHeading> headings, String anchor) {
  final wanted = markdownSlug(_decode(anchor));
  for (final heading in headings) {
    if (heading.slug == wanted) return heading;
  }
  return null;
}

/// Percent-decodes [anchor], but only when it is actually percent-encoded.
///
/// `Uri.decodeComponent` THROWS on raw non-ASCII — `decodeComponent('türkçe')`
/// is an "Illegal percent encoding" error, not a passthrough. Calling it
/// unconditionally therefore crashed on precisely the input D16 exists for: a
/// Turkish anchor somebody typed by hand.
String _decode(String anchor) {
  if (!anchor.contains('%')) return anchor;
  try {
    return Uri.decodeComponent(anchor);
  } on ArgumentError {
    // Half-encoded, or a stray `%` in a heading. The raw text is a better
    // guess than giving up on the jump.
    return anchor;
  }
}

/// Which heading a reader is "in" at [blockIndex] — the last one at or above
/// it. Drives the outline's current-section highlight (D13).
MdHeading? headingAt(List<MdHeading> headings, int blockIndex) {
  MdHeading? current;
  for (final heading in headings) {
    if (heading.blockIndex > blockIndex) break;
    current = heading;
  }
  return current;
}

/// The blocks a collapsed heading hides: everything after it, up to the next
/// heading at the same level or shallower (D14).
///
/// Returned as a range rather than applied, because **folding must never touch
/// the document**. It is a view state; the bytes are not ours to rewrite.
({int start, int end}) foldedRangeFor(
  MdDocument doc,
  List<MdHeading> headings,
  MdHeading heading,
) {
  final start = heading.blockIndex + 1;
  for (final other in headings) {
    if (other.blockIndex <= heading.blockIndex) continue;
    if (other.level <= heading.level) {
      return (start: start, end: other.blockIndex);
    }
  }
  return (start: start, end: doc.blocks.length);
}
