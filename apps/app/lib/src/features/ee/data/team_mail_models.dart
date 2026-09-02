/// A team's own mail relay, client side (OPH-290).
///
/// DELIBERATELY INCOMPLETE, the same way `EeIdentityProvider` and
/// `EeTeamAiConnection` are and for the same reason: the server keeps
/// ciphertext and four characters, and no response carries the password.
/// There is no `String? password` field here, because that field is the one
/// that invites somebody to add the endpoint that would fill it.
///
/// [missingRequired] is server-derived on purpose. The screen has to be able
/// to say "to start sending mail, fill these in" — a sentence you can only
/// write if something tells you WHICH, and a client keeping its own copy of
/// that rule would disagree with the server the first time it changed.
class EeTeamMail {
  const EeTeamMail({
    required this.configured,
    required this.enabled,
    required this.port,
    required this.secure,
    required this.passwordSet,
    required this.status,
    required this.missingRequired,
    this.host,
    this.username,
    this.fromAddress,
    this.fromName,
    this.passwordLast4,
    this.lastError,
    this.lastVerifiedAt,
  });

  factory EeTeamMail.fromJson(Map<String, dynamic> json) => EeTeamMail(
    configured: json['configured'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? false,
    host: json['host'] as String?,
    port: json['port'] as int? ?? 587,
    secure: json['secure'] as bool? ?? false,
    username: json['username'] as String?,
    fromAddress: json['fromAddress'] as String?,
    fromName: json['fromName'] as String?,
    passwordSet: json['passwordSet'] as bool? ?? false,
    passwordLast4: json['passwordLast4'] as String?,
    status: json['status'] as String? ?? 'active',
    lastError: json['lastError'] as String?,
    missingRequired: List<String>.from(
      json['missingRequired'] as List? ?? const <String>[],
    ),
    lastVerifiedAt: json['lastVerifiedAt'] == null
        ? null
        : DateTime.parse(json['lastVerifiedAt'] as String).toLocal(),
  );

  /// Whether a row exists at all. Different from [enabled]: a team can have
  /// settings saved and switched off, and the two need different sentences.
  final bool configured;

  /// Off until somebody has finished it. While this is false the team sends
  /// nothing — its messages wait in the queue rather than failing, and go out
  /// the moment it is switched on.
  final bool enabled;

  final String? host;
  final int port;

  /// Implicit TLS on connect (465) rather than STARTTLS after it (587). The
  /// server requires one of the two either way.
  final bool secure;

  final String? username;
  final String? fromAddress;
  final String? fromName;

  final bool passwordSet;

  /// Four characters, or null when none is stored. The whole of what anybody
  /// can learn here.
  final String? passwordLast4;

  /// `active`, or `error` when the relay last refused or could not be reached.
  final String status;
  final String? lastError;
  final DateTime? lastVerifiedAt;

  /// What this relay still needs before it can be switched on.
  final List<String> missingRequired;

  /// True when the team is actually sending. The one question the settings
  /// screen and the invite screen both need answered.
  bool get sending => enabled && missingRequired.isEmpty;
}

/// The answer to "does this relay work?" — one field, deliberately.
///
/// Unlike a directory, there is no useful difference here between "the relay
/// refused these credentials" and "the relay did not answer": both are fixed
/// in the same form, by the same person, in the next minute.
class EeTeamMailTestResult {
  const EeTeamMailTestResult({required this.ok, this.error});

  factory EeTeamMailTestResult.fromJson(Map<String, dynamic> json) =>
      EeTeamMailTestResult(
        ok: json['ok'] as bool? ?? false,
        error: json['error'] as String?,
      );

  final bool ok;
  final String? error;
}
