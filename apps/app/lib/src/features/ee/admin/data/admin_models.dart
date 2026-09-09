/// Models for the instance-operator console (EE-033).
///
/// The operator is NOT a workspace user — different table, different token
/// audience, different session on this device. These types stay in their own
/// folder for the same reason: nothing here should ever be reachable from a
/// person's own screens by accident.
library;

class AdminSession {
  const AdminSession({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  bool get isExpired => refreshExpiresAt.isBefore(DateTime.now());

  factory AdminSession.fromJson(Map<String, dynamic> json) => AdminSession(
    email: json['email'] as String? ?? '',
    accessToken: json['accessToken'] as String? ?? '',
    refreshToken: json['refreshToken'] as String? ?? '',
    refreshExpiresAt:
        DateTime.tryParse(json['refreshExpiresAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'email': email,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'refreshExpiresAt': refreshExpiresAt.toIso8601String(),
  };

  AdminSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? refreshExpiresAt,
  }) => AdminSession(
    email: email,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
  );
}

/// The seat banner. `exceeded` is "already over"; `canAdd` is "may one more
/// person join". Two questions a screen must not merge (EE-032).
class SeatStatus {
  const SeatStatus({
    required this.used,
    required this.pending,
    required this.max,
    required this.remaining,
    required this.exceeded,
    required this.canAdd,
  });

  final int used;
  final int pending;
  final int? max;
  final int? remaining;
  final bool exceeded;
  final bool canAdd;

  static const SeatStatus unknown = SeatStatus(
    used: 0,
    pending: 0,
    max: null,
    remaining: null,
    exceeded: false,
    canAdd: true,
  );

  factory SeatStatus.fromJson(Map<String, dynamic> json) => SeatStatus(
    used: (json['used'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    max: (json['max'] as num?)?.toInt(),
    remaining: (json['remaining'] as num?)?.toInt(),
    exceeded: json['exceeded'] as bool? ?? false,
    canAdd: json['canAdd'] as bool? ?? true,
  );
}

enum AdminTeamStatus {
  active,
  suspended,
  pendingDelete;

  static AdminTeamStatus parse(String? raw) => switch (raw) {
    'suspended' => AdminTeamStatus.suspended,
    'pending_delete' => AdminTeamStatus.pendingDelete,
    _ => AdminTeamStatus.active,
  };
}

class AdminTeam {
  const AdminTeam({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.packageName,
    required this.seatsUsed,
    required this.seatsLimit,
    required this.pendingDeleteAt,
  });

  final String id;
  final String name;
  final String slug;
  final AdminTeamStatus status;
  final String? packageName;
  final int seatsUsed;
  final int? seatsLimit;
  final DateTime? pendingDeleteAt;

  factory AdminTeam.fromJson(Map<String, dynamic> json) => AdminTeam(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    status: AdminTeamStatus.parse(json['status'] as String?),
    packageName: json['packageName'] as String?,
    seatsUsed: (json['seatsUsed'] as num?)?.toInt() ?? 0,
    seatsLimit: (json['seatsLimit'] as num?)?.toInt(),
    pendingDeleteAt: DateTime.tryParse(
      json['pendingDeleteAt'] as String? ?? '',
    ),
  );
}

class AdminPackage {
  const AdminPackage({
    required this.id,
    required this.name,
    required this.limits,
    required this.isDefault,
  });

  final String id;
  final String name;

  /// key → value, where `null` means "no ceiling" and an ABSENT key means
  /// "this package does not speak about that limit". The two are different
  /// answers and the editor keeps them different (EE-029).
  final Map<String, int?> limits;
  final bool isDefault;

  factory AdminPackage.fromJson(Map<String, dynamic> json) => AdminPackage(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    limits: {
      for (final entry
          in (json['limits'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: (entry.value as num?)?.toInt(),
    },
    isDefault: json['isDefault'] as bool? ?? false,
  );
}

/// One entry of the server's limit dictionary. The console is TOLD which keys
/// exist rather than hard-coding them, so a key added on the server appears in
/// the editor without an app release (EE-029's "registry + doc line").
class LimitKeyInfo {
  const LimitKeyInfo({
    required this.key,
    required this.kind,
    required this.unit,
    required this.enforced,
  });

  final String key;
  final String kind;
  final String unit;

  /// False when nothing counts this limit yet. The editor says so out loud —
  /// selling a ceiling the code does not apply is worse than not offering it.
  final bool enforced;

  factory LimitKeyInfo.fromJson(Map<String, dynamic> json) => LimitKeyInfo(
    key: json['key'] as String? ?? '',
    kind: json['kind'] as String? ?? 'quota',
    unit: json['unit'] as String? ?? '',
    enforced: json['enforced'] as bool? ?? false,
  );
}

class InstanceUsage {
  const InstanceUsage({
    required this.teamsUsed,
    required this.teamsMax,
    required this.rows,
  });

  final int teamsUsed;
  final int? teamsMax;
  final List<TeamUsage> rows;

  factory InstanceUsage.fromJson(Map<String, dynamic> json) {
    final teams =
        (json['instance'] as Map<String, dynamic>? ?? const {})['teams']
            as Map<String, dynamic>? ??
        const {};
    return InstanceUsage(
      teamsUsed: (teams['used'] as num?)?.toInt() ?? 0,
      teamsMax: (teams['max'] as num?)?.toInt(),
      rows: [
        for (final row in (json['teams'] as List<dynamic>? ?? const []))
          TeamUsage.fromJson(row as Map<String, dynamic>),
      ],
    );
  }
}

class TeamUsage {
  const TeamUsage({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.packageName,
    required this.seats,
    required this.workspaces,
  });

  final String id;
  final String name;
  final String slug;
  final AdminTeamStatus status;
  final String? packageName;
  final SeatStatus seats;
  final int workspaces;

  factory TeamUsage.fromJson(Map<String, dynamic> json) => TeamUsage(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    status: AdminTeamStatus.parse(json['status'] as String?),
    packageName: json['packageName'] as String?,
    seats: SeatStatus.fromJson(
      json['seats'] as Map<String, dynamic>? ?? const {},
    ),
    workspaces: (json['workspaces'] as num?)?.toInt() ?? 0,
  );
}

/// A minted invitation. Both halves are shown ONCE and never fetched again.
class MintedInvite {
  const MintedInvite({
    required this.email,
    required this.token,
    required this.code,
  });

  final String email;
  final String token;
  final String code;
}

/// One sales enquiry as the console reads it (EE-160, server EE-159).
///
/// `erased` is a FIELD rather than something the screen works out from the
/// empty columns. A screen that inferred it would draw the same blank for a
/// fulfilled erasure and for a row that arrived broken — and a discharged legal
/// obligation would read as a bug.
class AdminLead {
  const AdminLead({
    required this.id,
    required this.status,
    required this.locale,
    required this.erased,
    this.fullName,
    this.companyName,
    this.workEmail,
    this.phone,
    this.seatCount,
    this.unitCount,
    this.packageInterest,
    this.message,
    this.notes,
    this.consentVersion,
    this.consentAt,
    this.sourceIp,
    this.userAgent,
    this.referrer,
    this.statusChangedAt,
    this.erasedAt,
    this.createdAt,
  });

  final String id;
  final String status;
  final String locale;
  final bool erased;

  /// Every one of these is null on an erased row, and null on a row where the
  /// sender simply did not answer. `erased` is what tells the two apart.
  final String? fullName;
  final String? companyName;
  final String? workEmail;
  final String? phone;
  final int? seatCount;
  final int? unitCount;
  final String? packageInterest;
  final String? message;
  final String? notes;
  final String? consentVersion;
  final String? consentAt;
  final String? sourceIp;
  final String? userAgent;
  final String? referrer;
  final String? statusChangedAt;
  final String? erasedAt;
  final String? createdAt;

  factory AdminLead.fromJson(Map<String, dynamic> json) => AdminLead(
    id: json['id'] as String? ?? '',
    status: json['status'] as String? ?? 'new',
    locale: json['locale'] as String? ?? 'en',
    erased: json['erased'] as bool? ?? false,
    fullName: json['fullName'] as String?,
    companyName: json['companyName'] as String?,
    workEmail: json['workEmail'] as String?,
    phone: json['phone'] as String?,
    seatCount: (json['seatCount'] as num?)?.toInt(),
    unitCount: (json['unitCount'] as num?)?.toInt(),
    packageInterest: json['packageInterest'] as String?,
    message: json['message'] as String?,
    notes: json['notes'] as String?,
    consentVersion: json['consentVersion'] as String?,
    consentAt: json['consentAt'] as String?,
    sourceIp: json['sourceIp'] as String?,
    userAgent: json['userAgent'] as String?,
    referrer: json['referrer'] as String?,
    statusChangedAt: json['statusChangedAt'] as String?,
    erasedAt: json['erasedAt'] as String?,
    createdAt: json['createdAt'] as String?,
  );
}

/// The five states, in the order an enquiry moves through them.
///
/// Duplicated from the server's enum on purpose — the alternative is another
/// round trip to learn five words that change roughly never — and held to it by
/// `admin_leads_test.dart`, which insists every one has a translation in both
/// languages.
const kAdminLeadStatuses = <String>[
  'new',
  'contacted',
  'qualified',
  'won',
  'lost',
];

/// A page of leads plus the cursor that continues it.
///
/// `nextCursor` being null means the END, and that is an answer rather than
/// something to infer: a client comparing lengths guesses wrong on a page that
/// is exactly full.
class AdminLeadPage {
  const AdminLeadPage({required this.items, this.nextCursor});

  final List<AdminLead> items;
  final String? nextCursor;

  factory AdminLeadPage.fromJson(Map<String, dynamic> json) => AdminLeadPage(
    items: [
      for (final row in (json['items'] as List<dynamic>? ?? const []))
        AdminLead.fromJson(row as Map<String, dynamic>),
    ],
    nextCursor: json['nextCursor'] as String?,
  );
}
