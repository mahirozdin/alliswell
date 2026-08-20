/// The team-admin area's models (EE-042) — the client mirrors of the team
/// info, member and invitation surfaces.
///
/// Every one of these is a SERVER truth with no offline story: they describe
/// who may do what, and a stale answer to that question is worse than no
/// answer. That is why nothing here is cached (the sync roster, which IS
/// cached, is a different thing carrying different data — EE-017).
library;

/// `{used, pending, max, remaining, exceeded, canAdd}` — the banner every
/// decision on these screens is made against.
class EeSeats {
  const EeSeats({
    this.used = 0,
    this.pending = 0,
    this.max,
    this.remaining,
    this.exceeded = false,
    this.canAdd = true,
  });

  final int used;

  /// Outstanding invitations. Not members yet, so not counted as used — but
  /// counted against minting another one.
  final int pending;
  final int? max;
  final int? remaining;

  /// Already over the plan (a lowered limit). Nobody is evicted for it.
  final bool exceeded;

  /// May one more person join right now. A different question from
  /// [exceeded], and a screen that conflates them tells people to fix the
  /// wrong thing.
  final bool canAdd;

  factory EeSeats.fromJson(Map<String, dynamic> json) => EeSeats(
    used: (json['used'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    max: (json['max'] as num?)?.toInt(),
    remaining: (json['remaining'] as num?)?.toInt(),
    exceeded: json['exceeded'] as bool? ?? false,
    canAdd: json['canAdd'] as bool? ?? true,
  );
}

/// What the team is, and where the caller stands in it.
class EeTeamInfo {
  const EeTeamInfo({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    this.memberCount = 0,
    this.myRole,
    this.seats,
  });

  final String id;
  final String name;
  final String slug;

  /// `active | suspended | pending_delete`. A suspended team is readable and
  /// not writable — the surfaces stay, the buttons stop.
  final String status;
  final int memberCount;

  /// `owner | admin | member`, or null when the caller is not in this team.
  final String? myRole;

  /// Present only for owners and admins (the server decides).
  final EeSeats? seats;

  bool get isAdmin => myRole == 'owner' || myRole == 'admin';
  bool get isFrozen => status != 'active';

  factory EeTeamInfo.fromJson(Map<String, dynamic> json) => EeTeamInfo(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'active',
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    myRole: json['myRole'] as String?,
    seats: json['seats'] == null
        ? null
        : EeSeats.fromJson((json['seats'] as Map).cast<String, dynamic>()),
  );
}

/// One row of the management roster. Carries the e-mail, unlike the sync
/// roster: this is the screen where somebody decides who to remove, and
/// "which Ada?" is not a question initials can answer.
class EeTeamMember {
  const EeTeamMember({
    required this.userId,
    required this.role,
    required this.active,
    this.email,
    this.displayName,
    this.initials,
    this.colorRgb,
    this.joinedAt,
    this.deactivatedAt,
  });

  final String userId;
  final String role;

  /// False for a deactivated member: their row and role survive, their access
  /// does not, and their seat is free.
  final bool active;
  final String? email;
  final String? displayName;
  final String? initials;
  final String? colorRgb;
  final String? joinedAt;
  final String? deactivatedAt;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName! : (email ?? userId);

  factory EeTeamMember.fromJson(Map<String, dynamic> json) => EeTeamMember(
    userId: (json['userId'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'member',
    active: json['active'] as bool? ?? true,
    email: json['email'] as String?,
    displayName: json['displayName'] as String?,
    initials: json['initials'] as String?,
    colorRgb: json['colorRgb'] as String?,
    joinedAt: json['joinedAt'] as String?,
    deactivatedAt: json['deactivatedAt'] as String?,
  );
}

/// The roster plus the banner it is read against — they arrive together
/// because no decision on that screen is made without both.
class EeTeamRoster {
  const EeTeamRoster({required this.members, required this.seats});
  final List<EeTeamMember> members;
  final EeSeats seats;

  factory EeTeamRoster.fromJson(Map<String, dynamic> json) => EeTeamRoster(
    members: ((json['items'] as List?) ?? const [])
        .map((e) => EeTeamMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    seats: EeSeats.fromJson(
      ((json['seats'] as Map?) ?? const {}).cast<String, dynamic>(),
    ),
  );
}

/// An invitation as a LISTING shows it. No credential fields exist here and
/// none ever will: only digests were stored, so there is nothing to show.
class EeInvite {
  const EeInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.state,
    required this.expiresAt,
    this.createdBy,
  });

  final String id;
  final String email;
  final String role;

  /// `pending | accepted | revoked | expired | burned`. One vocabulary,
  /// shared with the server, so a screen and a server never describe the same
  /// row with different words.
  final String state;
  final String expiresAt;
  final String? createdBy;

  bool get isLive => state == 'pending';

  factory EeInvite.fromJson(Map<String, dynamic> json) => EeInvite(
    id: (json['id'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'member',
    state: (json['state'] as String?) ?? 'pending',
    expiresAt: (json['expiresAt'] as String?) ?? '',
    createdBy: json['createdBy'] as String?,
  );
}

/// What minting an invitation answers — and the ONLY time the two halves of
/// the credential are ever visible. Nothing can read them back.
class EeMintedInvite {
  const EeMintedInvite({
    required this.invite,
    required this.token,
    required this.code,
    required this.link,
    required this.delivery,
  });

  final EeInvite invite;
  final String token;

  /// The six digits. Shown APART from the link on purpose: they travel by a
  /// different path, and a screen that offers "copy both" would undo the
  /// reason there are two.
  final String code;
  final String link;

  /// `mail` → the server queued a message. `manual` → this instance sends no
  /// mail, so the admin is the delivery mechanism and needs to be told.
  final String delivery;

  bool get sendsMail => delivery == 'mail';

  factory EeMintedInvite.fromJson(Map<String, dynamic> json) => EeMintedInvite(
    invite: EeInvite.fromJson(
      ((json['invite'] as Map?) ?? const {}).cast<String, dynamic>(),
    ),
    token: (json['token'] as String?) ?? '',
    code: (json['code'] as String?) ?? '',
    link: (json['link'] as String?) ?? '',
    delivery: (json['delivery'] as String?) ?? 'manual',
  );
}
