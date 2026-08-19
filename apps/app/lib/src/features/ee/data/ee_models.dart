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
