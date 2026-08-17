/// API keys as the server describes them (OPH-265, ADR-0032).
///
/// There is no `key` field here on purpose: the secret exists in exactly one
/// HTTP response and is handed straight to the dialog that shows it. Putting
/// it on the model would invite somebody to hold on to it.
class ApiKey {
  const ApiKey({
    required this.id,
    required this.name,
    required this.keyPrefix,
    required this.createdAt,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String name;

  /// `awk_` plus the first characters — recognition, never authentication.
  final String keyPrefix;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  /// Whether this key would authenticate a request right now.
  bool get isLive => !isRevoked && !isExpired;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value as String);

  factory ApiKey.fromJson(Map<String, dynamic> json) => ApiKey(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    keyPrefix: json['keyPrefix'] as String? ?? '',
    createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
    expiresAt: _date(json['expiresAt']),
    lastUsedAt: _date(json['lastUsedAt']),
    revokedAt: _date(json['revokedAt']),
  );
}

/// A freshly minted key: the row PLUS the one-time secret.
class NewApiKey {
  const NewApiKey({required this.key, required this.row});

  /// The `awk_…` secret. Shown once, never stored by the app.
  final String key;
  final ApiKey row;

  factory NewApiKey.fromJson(Map<String, dynamic> json) =>
      NewApiKey(key: json['key'] as String? ?? '', row: ApiKey.fromJson(json));
}

/// The lifetimes the create sheet offers (ADR-0032 / the server's enum).
/// `null` is "no expiry" — an honest option, not a hidden default.
const List<int?> kApiKeyLifetimes = [30, 90, 365, null];
