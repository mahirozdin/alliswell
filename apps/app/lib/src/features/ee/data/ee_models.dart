/// Instance entitlement status (EE-008) — the client mirror of
/// `GET /api/v1/ee/status` (capability discovery, always registered
/// server-side). Feature names are opaque strings here: the server owns the
/// dictionary, so an unknown name simply never appears in the list.
class EeStatus {
  const EeStatus({
    required this.state,
    this.features = const [],
    this.expiresAt,
    this.overlay = 'disabled',
    this.baseDomain,
  });

  /// License lifecycle: `none | active | grace | readonly`.
  final String state;

  /// The instance's licensed feature names (coarse product areas).
  final List<String> features;

  /// ISO-8601 license expiry, when one applies.
  final String? expiresAt;

  /// Overlay diagnostics: `disabled | absent | loaded | error`.
  final String overlay;

  /// The apex domain this instance serves, when it serves one. A client
  /// cannot tell a tenant host from an ordinary one by looking at it, so the
  /// server says it rather than the app guessing from label counts.
  final String? baseDomain;

  /// The CE truth — also what a 404 (a server that predates the endpoint)
  /// maps to: nothing enabled, not an error.
  static const EeStatus none = EeStatus(state: 'none');

  /// Mirrors the server's `has()`: a feature is on only while the license
  /// breathes (active or grace). `readonly` keeps names listed but answers
  /// false — surfaces decide their own read-only presentation later.
  bool has(String feature) =>
      (state == 'active' || state == 'grace') && features.contains(feature);

  factory EeStatus.fromJson(Map<String, dynamic> json) => EeStatus(
    state: (json['state'] as String?) ?? 'none',
    features: ((json['features'] as List?) ?? const []).cast<String>(),
    expiresAt: json['expiresAt'] as String?,
    overlay: (json['overlay'] as String?) ?? 'disabled',
    baseDomain: json['baseDomain'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'state': state,
    'features': features,
    'expiresAt': expiresAt,
    'overlay': overlay,
    'baseDomain': baseDomain,
  };
}

/// What THIS person may do in ONE workspace (EE-052) — the client mirror of
/// `GET /api/v1/ee/me/permissions`.
///
/// [governed] is the field that keeps this honest, and it is not the same as
/// an empty [permissions] list. `governed: false` means nothing is asking:
/// a personal workspace, a plain build, an instance without the feature. Then
/// every [can] answers TRUE, because that is exactly what the product does
/// today and a permission layer must not remove abilities where it is not
/// installed. An empty list under `governed: true` is the opposite — a role
/// that really may do nothing.
class EePermissions {
  const EePermissions({
    required this.workspaceId,
    required this.governed,
    this.permissions = const [],
  });

  factory EePermissions.fromJson(Map<String, dynamic> json) => EePermissions(
    workspaceId: (json['workspaceId'] as String?) ?? '',
    governed: (json['governed'] as bool?) ?? false,
    permissions: ((json['permissions'] as List?) ?? const []).cast<String>(),
  );

  final String workspaceId;
  final bool governed;
  final List<String> permissions;

  /// The answer a screen asks for before it draws a button.
  bool can(String permission) => !governed || permissions.contains(permission);

  /// Ungoverned: the honest answer while signed out, offline with no cache,
  /// or on an instance that has no such feature.
  static const EePermissions unknown = EePermissions(
    workspaceId: '',
    governed: false,
  );

  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'governed': governed,
    'permissions': permissions,
  };
}
