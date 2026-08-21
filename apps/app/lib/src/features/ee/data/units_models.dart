/// Units and their people (EE-057).
///
/// A unit is a workspace with a name and a roster. What the client models is
/// deliberately thinner than the server's picture: the app never learns WHY it
/// may act on a unit — only that the server handed this one over. Authority
/// over a unit is held two ways (team-wide, or delegated to this one unit) and
/// deciding which is the server's job; a client that reimplemented that rule
/// would be a second copy of it, drifting from the first.
class EeUnit {
  const EeUnit({
    required this.id,
    required this.name,
    this.archived = false,
    this.memberCount = 0,
    this.workspaceIds = const [],
    this.manages = false,
  });

  factory EeUnit.fromJson(Map<String, dynamic> json) => EeUnit(
    id: json['id'] as String,
    name: json['name'] as String,
    archived: (json['archived'] as bool?) ?? false,
    memberCount: (json['memberCount'] as int?) ?? 0,
    workspaceIds: ((json['workspaceIds'] as List?) ?? const []).cast<String>(),
    manages: (json['manages'] as bool?) ?? false,
  );

  final String id;
  final String name;
  final bool archived;

  /// How many people are in it. On the row rather than one screen deeper, for
  /// the same reason the role list carries it: "may I narrow this?" cannot be
  /// answered without knowing who it touches.
  final int memberCount;
  final List<String> workspaceIds;

  /// True when the caller is a DELEGATED manager of this unit — not merely
  /// allowed to act on it. A team admin may do everything here and still see
  /// `false`, because the flag answers "is this mine to run?", which is what
  /// the screen needs in order to explain itself.
  final bool manages;
}

class EeUnitMember {
  const EeUnitMember({
    required this.userId,
    required this.role,
    this.displayName,
    this.email,
  });

  factory EeUnitMember.fromJson(Map<String, dynamic> json) => EeUnitMember(
    userId: json['userId'] as String,
    role: (json['role'] as String?) ?? 'member',
    displayName: json['displayName'] as String?,
    email: json['email'] as String?,
  );

  final String userId;

  /// `member` or `manager`.
  final String role;
  final String? displayName;
  final String? email;

  bool get isManager => role == 'manager';

  /// What to render. An account with no display name still has an address,
  /// and a row with neither is a row nobody can act on.
  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName! : (email ?? userId);
}
