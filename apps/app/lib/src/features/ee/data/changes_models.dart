import '../../../sync/db/database.dart';

/// A planned change (EE-186, screens EE-269).
///
/// Two sources fill it and the screens keep them apart. The device's copy
/// ([EeChange.fromRecord]) carries what a replica row holds — enough to read a
/// plan with no signal. The server's answer ([EeChange.fromJson]) adds what
/// only the server knows: which services it touches and which request it was
/// raised from (EE-279). [fromServer] says which one a screen is holding.
class EeChange {
  const EeChange({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.type,
    required this.status,
    required this.risk,
    required this.impact,
    this.description,
    this.rollbackPlan,
    this.windowStart,
    this.windowEnd,
    this.serviceIds = const [],
    this.sourceTicketId,
    this.createdAt,
    this.fromServer = false,
  });

  factory EeChange.fromRecord(ChangeRecord row) => EeChange(
    id: row.id,
    workspaceId: row.workspaceId,
    title: row.title,
    description: row.description,
    type: row.type,
    status: row.status,
    risk: row.risk,
    impact: row.impact,
    rollbackPlan: row.rollbackPlan,
    windowStart: row.windowStart?.toLocal(),
    windowEnd: row.windowEnd?.toLocal(),
    createdAt: row.createdAt?.toLocal(),
  );

  factory EeChange.fromJson(Map<String, dynamic> json) => EeChange(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    type: json['type'] as String,
    status: json['status'] as String,
    risk: json['risk'] as String,
    impact: json['impact'] as String,
    rollbackPlan: json['rollbackPlan'] as String?,
    windowStart: _date(json['windowStart']),
    windowEnd: _date(json['windowEnd']),
    serviceIds: [
      for (final id in (json['serviceIds'] as List<dynamic>? ?? const []))
        id as String,
    ],
    sourceTicketId: json['sourceTicketId'] as String?,
    createdAt: _date(json['createdAt']),
    fromServer: true,
  );

  final String id;
  final String workspaceId;
  final String title;
  final String? description;

  /// `standard | normal | emergency`, the server's own word.
  final String type;

  /// The server's own word, drawn as it is. The screens never decide what may
  /// follow it: that is the server's map (§0.0/6 — no second state machine).
  final String status;

  /// `low | medium | high`.
  final String risk;
  final String impact;
  final String? rollbackPlan;
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Server-only (the replica row has no column for them).
  final List<String> serviceIds;
  final String? sourceTicketId;
  final DateTime? createdAt;
  final bool fromServer;

  bool get hasWindow => windowStart != null && windowEnd != null;
}

/// Another change standing on one of this change's services in its window
/// (EE-187's clash: it warns, it does not refuse).
class EeChangeClash {
  const EeChangeClash({
    required this.changeId,
    required this.title,
    required this.status,
    required this.windowStart,
    required this.windowEnd,
  });

  factory EeChangeClash.fromJson(Map<String, dynamic> json) => EeChangeClash(
    changeId: json['changeId'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    windowStart: DateTime.parse(json['windowStart'] as String).toLocal(),
    windowEnd: DateTime.parse(json['windowEnd'] as String).toLocal(),
  );

  final String changeId;
  final String title;
  final String status;
  final DateTime windowStart;
  final DateTime windowEnd;
}

/// A period the company declared nothing moves in (EE-187's freeze).
class EeChangeFreeze {
  const EeChangeFreeze({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.reason,
  });

  factory EeChangeFreeze.fromJson(Map<String, dynamic> json) => EeChangeFreeze(
    id: json['id'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
    endsAt: DateTime.parse(json['endsAt'] as String).toLocal(),
    reason: json['reason'] as String,
  );

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String reason;
}

/// What the calendar says about ONE change's window: the changes it clashes
/// with and the freezes it overlaps, each by name.
class EeChangeConflicts {
  const EeChangeConflicts({this.clashes = const [], this.freezes = const []});

  final List<EeChangeClash> clashes;
  final List<EeChangeFreeze> freezes;

  bool get isEmpty => clashes.isEmpty && freezes.isEmpty;
}

/// One signature asked for on a change (EE-184's row, seen from the change).
class EeChangeApproval {
  const EeChangeApproval({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.canDecide,
    this.approverUserId,
    this.approverRoleKey,
    this.approverName,
    this.requestReason,
    this.decidedByName,
    this.decidedAt,
    this.decisionReason,
  });

  factory EeChangeApproval.fromJson(Map<String, dynamic> json) =>
      EeChangeApproval(
        id: json['id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        canDecide: (json['canDecide'] as bool?) ?? false,
        approverUserId: json['approverUserId'] as String?,
        approverRoleKey: json['approverRoleKey'] as String?,
        approverName: json['approverName'] as String?,
        requestReason: json['requestReason'] as String?,
        decidedByName: json['decidedByName'] as String?,
        decidedAt: _date(json['decidedAt']),
        decisionReason: json['decisionReason'] as String?,
      );

  final String id;

  /// `pending | approved | rejected | …`, the server's word.
  final String status;
  final DateTime createdAt;

  /// The decision door's own rule, asked on the server: the row names this
  /// person (or a role they hold) AND they hold `approvals.decide`. The
  /// buttons follow it; the door still decides.
  final bool canDecide;
  final String? approverUserId;
  final String? approverRoleKey;

  /// A person's name or a custom role's; null for a built-in role, whose
  /// word the app has in both languages.
  final String? approverName;
  final String? requestReason;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionReason;

  bool get isPending => status == 'pending';
}

/// A machine a change touches (EE-192's link, read for the change).
class EeChangeAsset {
  const EeChangeAsset({
    required this.assetId,
    required this.tag,
    required this.name,
    required this.status,
    this.location,
  });

  factory EeChangeAsset.fromJson(Map<String, dynamic> json) => EeChangeAsset(
    assetId: json['assetId'] as String,
    tag: json['tag'] as String,
    name: json['name'] as String,
    status: json['status'] as String,
    location: json['location'] as String?,
  );

  final String assetId;
  final String tag;
  final String name;
  final String status;
  final String? location;
}

/// Everything the detail reads from the server in one go: the parts a replica
/// row cannot carry. Asked every time the detail opens, never kept — a
/// signature given a minute ago must not be drawn as still pending.
class EeChangeLive {
  const EeChangeLive({
    required this.change,
    this.approvals = const [],
    this.assets = const [],
    this.conflicts,
  });

  /// The server's own copy: services and the source request live here.
  final EeChange change;
  final List<EeChangeApproval> approvals;
  final List<EeChangeAsset> assets;

  /// Null when the change has no window: it is in no calendar.
  final EeChangeConflicts? conflicts;
}

/// Where a change opened from a request comes from (EE-279).
class EeChangeSource {
  const EeChangeSource({
    required this.ticketId,
    required this.subject,
    this.number,
  });

  final String ticketId;
  final String subject;
  final int? number;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
