import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kv/local_kv.dart';

/// The colours you reached for last, across every picker (OPH-259, §33 R2).
///
/// **One memory, not one per screen.** The colour you just gave a project is
/// the colour you are about to give a tag or a highlight; a per-surface list
/// would forget exactly when it mattered. Device-local like every other
/// viewing preference — nothing here syncs.
const kAwRecentColorsKey = 'alliswell_recent_colors';

/// Kept a little longer than shown, so a surface whose palette holds only two
/// of your last five still has older ones to fall back on.
const kAwRecentColorsKept = 8;
const kAwRecentColorsShown = 5;

/// Most-recent-first, upper-case `#RRGGBB`.
class RecentColors extends Notifier<List<String>> {
  @override
  List<String> build() {
    _hydrate();
    return const [];
  }

  Future<void> _hydrate() async {
    final raw = await localKv.get(kAwRecentColorsKey);
    if (raw == null) return;
    final decoded = _decode(raw);
    if (decoded.isNotEmpty) state = decoded;
  }

  /// Records a pick. Re-picking a colour moves it to the front rather than
  /// duplicating it — a list of the same colour five times is not a memory.
  Future<void> remember(String hex) async {
    final value = hex.toUpperCase();
    final next = [
      value,
      for (final existing in state)
        if (existing != value) existing,
    ].take(kAwRecentColorsKept).toList();
    state = next;
    await localKv.set(kAwRecentColorsKey, jsonEncode(next));
  }

  static List<String> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry.toUpperCase(),
      ].take(kAwRecentColorsKept).toList();
    } on FormatException {
      // A preference is never worth a crash; a junk value is just no memory.
      return const [];
    }
  }
}

final recentColorsProvider = NotifierProvider<RecentColors, List<String>>(
  RecentColors.new,
);

/// The recents a surface may actually offer: its OWN palette, newest first,
/// capped at [kAwRecentColorsShown].
///
/// The intersection is the point (§33 R2). Quick Access bounds its dot to ten
/// verified colours so the ring keeps its contrast promise (§23 Q8a), and the
/// editor's highlights are chosen to keep body text readable — letting a
/// remembered colour in from another surface would quietly break both.
List<String> awRecentColorsFor(List<String> recents, List<String> palette) {
  // Both sides normalised: what is stored is upper-case, but a palette
  // constant written in lower case must not silently empty the row.
  final allowed = {for (final hex in palette) hex.toUpperCase()};
  return [
    for (final hex in recents)
      if (allowed.contains(hex.toUpperCase())) hex.toUpperCase(),
  ].take(kAwRecentColorsShown).toList();
}
