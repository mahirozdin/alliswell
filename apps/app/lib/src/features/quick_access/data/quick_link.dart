/// The Quick Access model (OPH-198, BLUEPRINT §4.12, ADR-0018).
///
/// A shortcut stores `kind` + `targetId`, never a route string: routes are a
/// client concern (ADR-0016) and ids survive renames and router refactors.
library;

/// What a shortcut points at.
enum QuickKind {
  project,
  task,
  note,
  folder,
  file,
  url;

  static QuickKind? parse(String raw) {
    for (final kind in QuickKind.values) {
      if (kind.name == raw) return kind;
    }
    return null; // a newer server kind — the row is simply skipped
  }

  bool get isEntity => this != QuickKind.url;
}

/// One row of the user's rail, exactly as it is stored and synced.
class QuickLink {
  const QuickLink({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.kind,
    required this.title,
    this.targetId,
    this.url,
    this.emoji,
    this.colorRgb,
    this.sortOrder = 0,
  });

  final String id;
  final String workspaceId;
  final String userId;
  final QuickKind kind;
  final String title;
  final String? targetId;
  final String? url;
  final String? emoji;
  final String? colorRgb;
  final int sortOrder;
}

/// A rail row joined to the live state of its target.
///
/// The target is resolved from the REPLICA, so the rail is honest offline: a
/// renamed project shows its new name as a hint, an archived one renders
/// muted, and a target that is gone is [isBroken] until the server's cascade
/// arrives (OPH-203 owns that behaviour).
class QuickAccessRow {
  const QuickAccessRow({
    required this.link,
    this.targetTitle,
    this.targetColorRgb,
    this.isArchived = false,
    this.isCompleted = false,
    this.isBroken = false,
  });

  final QuickLink link;

  /// The target's CURRENT name, when the replica knows it.
  final String? targetTitle;
  final String? targetColorRgb;
  final bool isArchived;
  final bool isCompleted;

  /// An entity shortcut whose target is not in the replica.
  final bool isBroken;

  String get id => link.id;

  /// What the row shows: the user's own title always wins (BLUEPRINT §4.12 —
  /// the title is suggested from the target but belongs to the user).
  String get displayTitle => link.title;

  /// True when the target has since been renamed, so the row can offer to
  /// re-sync the name instead of silently drifting.
  bool get targetRenamed =>
      targetTitle != null && targetTitle!.trim() != link.title.trim();
}
