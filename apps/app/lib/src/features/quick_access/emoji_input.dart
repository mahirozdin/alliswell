/// Emoji input for Quick Access (OPH-202, DESIGN §23 Q7) — pure, no widgets.
///
/// No emoji-picker package: the system keyboard's own emoji page IS the real
/// picker on every mobile platform, and a full grid dependency would need an
/// ADR it cannot justify. What ships instead is a curated grid, the user's
/// recents, and a free text field that accepts exactly one grapheme.
library;

import 'package:flutter/widgets.dart';

/// How many recents the sheet remembers.
const int kQuickEmojiRecentsLimit = 16;

/// The curated grid: work-shaped, not a novelty set.
const List<String> kQuickEmojiGrid = [
  '⭐',
  '🔥',
  '✅',
  '📌',
  '📎',
  '📁',
  '📝',
  '📅',
  '⏰',
  '🎯',
  '🚀',
  '💡',
  '🧠',
  '📊',
  '💼',
  '🏷️',
  '🔔',
  '🔒',
  '🔗',
  '📥',
  '📤',
  '🗂️',
  '🧾',
  '💳',
  '🏠',
  '🏢',
  '✈️',
  '🚗',
  '🍽️',
  '☕',
  '🎵',
  '🎮',
  '❤️',
  '😀',
  '👍',
  '🙌',
  '🤝',
  '👤',
  '👨‍👩‍👧‍👦',
  '🐾',
  '🌱',
  '🌍',
  '☀️',
  '🌙',
  '⚡',
  '🎉',
  '🧩',
  '🛠️',
];

/// Accepts a single grapheme, rejects everything else (returns null).
///
/// One grapheme, not "is this an emoji": classifying emoji without a package
/// is guesswork that rejects real ones (flags, ZWJ families, keycaps), and a
/// user who wants "A" as their icon is not making a mistake.
///
/// Graphemes, not code points: a family emoji is seven code points and 25
/// bytes but ONE grapheme, and refusing it would be refusing an emoji for
/// being complicated. `String.characters` comes from `package:characters`,
/// re-exported by `flutter/widgets` — no new dependency.
String? normalizeEmojiInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.characters.length == 1 ? trimmed : null;
}

/// Reads the stored recents (comma-joined; an emoji can never contain a comma).
///
/// Tolerant like every other stored preference: entries that are no longer a
/// single grapheme — or plain junk — are dropped instead of throwing.
List<String> parseEmojiRecents(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final out = <String>[];
  for (final part in raw.split(',')) {
    final emoji = normalizeEmojiInput(part);
    if (emoji != null && !out.contains(emoji)) out.add(emoji);
  }
  return out.length <= kQuickEmojiRecentsLimit
      ? out
      : out.sublist(0, kQuickEmojiRecentsLimit);
}

/// Most-recent-first, deduplicated, capped.
List<String> pushEmojiRecent(List<String> recents, String emoji) {
  final normalized = normalizeEmojiInput(emoji);
  if (normalized == null) return recents;
  final out = [normalized, ...recents.where((e) => e != normalized)];
  return out.length <= kQuickEmojiRecentsLimit
      ? out
      : out.sublist(0, kQuickEmojiRecentsLimit);
}

String encodeEmojiRecents(List<String> recents) => recents.join(',');
