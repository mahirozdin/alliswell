/// How a list is ordered, and how that choice is stored (DESIGN §34, OPH-258).
///
/// Sorting is a *viewing* preference, not data: it lives on the device that
/// chose it, in one string per surface (`alliswell_notes_sort`), exactly like
/// the view mode next to it. Nothing here syncs.
///
/// Deliberately not an enum: each surface has its own option set (notes sort by
/// edited/created/title, files by date/name/size), and a shared menu widget has
/// to render whichever it is handed.
library;

/// One way a list can be ordered, plus which direction reads as "natural".
class AwSortChoice {
  const AwSortChoice({
    required this.id,
    required this.labelKey,
    this.descendingByDefault = true,
  });

  /// Stored in the preference — keep it stable, it outlives the label.
  final String id;
  final String labelKey;

  /// Newest first, biggest first — but names go A→Z. Picking a field gives you
  /// this direction, so "Title" never opens the list at Z.
  final bool descendingByDefault;
}

/// Which field a list is sorted by and which way, as one persisted string.
class AwSortState {
  const AwSortState(this.id, {this.descending = true});

  final String id;
  final bool descending;

  String encode() => '$id:${descending ? 'desc' : 'asc'}';

  /// Tolerates anything: an unknown field (a preference that outlived its
  /// option, or a newer peer's) falls back to the surface's first choice, and
  /// a missing direction takes the field's natural one.
  static AwSortState parse(String raw, List<AwSortChoice> choices) {
    final parts = raw.split(':');
    final choice = choices.firstWhere(
      (c) => c.id == parts.first,
      orElse: () => choices.first,
    );
    if (parts.length < 2 || (parts[1] != 'asc' && parts[1] != 'desc')) {
      return AwSortState(choice.id, descending: choice.descendingByDefault);
    }
    return AwSortState(choice.id, descending: parts[1] == 'desc');
  }

  /// Switching fields adopts the new field's natural direction; re-picking the
  /// field already in use changes nothing (so it cannot silently un-reverse).
  AwSortState select(AwSortChoice choice) => choice.id == id
      ? this
      : AwSortState(choice.id, descending: choice.descendingByDefault);

  AwSortState reversed() => AwSortState(id, descending: !descending);

  /// Reads [ascending] in the chosen direction. Comparators are always written
  /// ascending; this is the only place direction is applied.
  Comparator<T> comparator<T>(Comparator<T> ascending) =>
      descending ? (a, b) => ascending(b, a) : ascending;

  @override
  bool operator ==(Object other) =>
      other is AwSortState && other.id == id && other.descending == descending;

  @override
  int get hashCode => Object.hash(id, descending);

  @override
  String toString() => 'AwSortState(${encode()})';
}
