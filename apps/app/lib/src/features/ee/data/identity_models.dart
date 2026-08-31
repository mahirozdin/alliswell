/// A team's identity providers, client side (OPH-287).
///
/// DELIBERATELY INCOMPLETE, the same way `EeTeamAiConnection` is and for the
/// same reason stated there: the server keeps ciphertext and four characters,
/// and no response carries the credential. There is no `String? secret` field
/// here, because that field is the one that invites somebody to add the
/// endpoint that would fill it.
///
/// What the screen may know: whether a secret is stored ([secretSet]), its
/// last four characters ([secretLast4]), and — because a provider cannot be
/// switched on half-finished — exactly which settings are still missing
/// ([missingRequired]). That last one is server-derived on purpose: the rule
/// about what a type needs lives in one dictionary, and a screen that kept its
/// own copy would disagree with it the first time a type gained a field.
class EeIdentityProvider {
  const EeIdentityProvider({
    required this.id,
    required this.type,
    required this.displayName,
    required this.enabled,
    required this.priority,
    required this.status,
    required this.config,
    required this.secretSet,
    required this.missingRequired,
    this.secretLast4,
    this.secretField,
    this.lastError,
    this.lastVerifiedAt,
  });

  factory EeIdentityProvider.fromJson(Map<String, dynamic> json) =>
      EeIdentityProvider(
        id: json['id'] as String,
        type: json['type'] as String,
        displayName: json['displayName'] as String,
        enabled: json['enabled'] as bool? ?? false,
        priority: json['priority'] as int? ?? 100,
        status: json['status'] as String? ?? 'active',
        config: Map<String, dynamic>.from(
          json['config'] as Map? ?? const <String, dynamic>{},
        ),
        secretSet: json['secretSet'] as bool? ?? false,
        secretLast4: json['secretLast4'] as String?,
        secretField: json['secretField'] as String?,
        lastError: json['lastError'] as String?,
        missingRequired: List<String>.from(
          json['missingRequired'] as List? ?? const <String>[],
        ),
        lastVerifiedAt: json['lastVerifiedAt'] == null
            ? null
            : DateTime.parse(json['lastVerifiedAt'] as String).toLocal(),
      );

  final String id;

  /// `ldap`, `saml` or `oidc` — the server's dictionary decides, not this file.
  final String type;
  final String displayName;

  /// Off until somebody has finished it. A provider is born disabled because
  /// an enabled one is the ONLY authority for the addresses it owns.
  final bool enabled;

  /// Ask-order among this team's providers.
  final int priority;

  /// `active`, or `error` when the directory last refused or could not answer.
  final String status;

  /// The non-secret settings, per type. Never carries the credential: the
  /// server refuses a config that names one rather than quietly dropping it.
  final Map<String, dynamic> config;

  final bool secretSet;

  /// Four characters, or null when none is stored. The whole of what anybody
  /// can learn here.
  final String? secretLast4;

  /// Which config field IS the secret for this type, or null for a type that
  /// has none (SAML trusts a signature, not a shared key).
  final String? secretField;

  final String? lastError;
  final DateTime? lastVerifiedAt;

  /// What this provider still needs before it can be switched on.
  final List<String> missingRequired;

  /// True when everything the type requires is present. The screen asks this
  /// rather than deciding it, so there is one answer and the server owns it.
  bool get ready =>
      missingRequired.isEmpty && (secretField == null || secretSet);
}

/// The answer to "does this connection work?" — and the two ways it can be no.
///
/// [reason] is the directory REFUSING (a wrong bind password, no such entry);
/// [error] is the directory failing to answer at all. They are kept apart for
/// the reason the sign-in path keeps them apart: one is something to correct
/// in this form, the other is something to fix on the network.
class EeIdentityTestResult {
  const EeIdentityTestResult({required this.ok, this.reason, this.error});

  factory EeIdentityTestResult.fromJson(Map<String, dynamic> json) =>
      EeIdentityTestResult(
        ok: json['ok'] as bool? ?? false,
        reason: json['reason'] as String?,
        error: json['error'] as String?,
      );

  final bool ok;
  final String? reason;
  final String? error;
}

/// What a provisioning client has been doing (OPH-289).
///
/// No token and no way to ask for one: the server keeps a digest. What a
/// screen may know is the name, whether it is on, four characters, and — the
/// number this whole surface exists for — WHEN IT LAST DID ANYTHING. A client
/// that stopped calling is the failure nobody notices, and it looks exactly
/// like a quiet week unless somebody can see the date.
class EeScimClient {
  const EeScimClient({
    required this.id,
    required this.name,
    required this.enabled,
    this.tokenLast4,
    this.lastUsedAt,
  });

  factory EeScimClient.fromJson(Map<String, dynamic> json) => EeScimClient(
    id: json['id'] as String,
    name: json['name'] as String,
    enabled: json['enabled'] as bool? ?? false,
    tokenLast4: json['tokenLast4'] as String?,
    lastUsedAt: json['lastUsedAt'] == null
        ? null
        : DateTime.parse(json['lastUsedAt'] as String).toLocal(),
  );

  final String id;
  final String name;
  final bool enabled;
  final String? tokenLast4;
  final DateTime? lastUsedAt;
}

/// One thing that did not work, and why (OPH-289).
///
/// `subject` is whatever the provider or the client actually sent — an
/// address, a userName, a distinguished name — kept as it arrived, because a
/// report that shows the cleaned value cannot explain what was wrong with the
/// value. That is EE-123's rule about its import report, and it is the same
/// rule here.
class EeIdentityEvent {
  const EeIdentityEvent({
    required this.id,
    required this.kind,
    required this.outcome,
    required this.code,
    required this.at,
    this.detail,
    this.subject,
  });

  factory EeIdentityEvent.fromJson(Map<String, dynamic> json) =>
      EeIdentityEvent(
        id: json['id'] as String,
        kind: json['kind'] as String,
        outcome: json['outcome'] as String,
        code: json['code'] as String,
        detail: json['detail'] as String?,
        subject: json['subject'] as String?,
        at: DateTime.parse(json['at'] as String).toLocal(),
      );

  final String id;

  /// `sign_in`, `provision`, `deprovision`, `group_sync`, `connection`.
  final String kind;

  /// `refused` (we said no), `failed` (something broke), `ok`.
  final String outcome;
  final String code;
  final String? detail;
  final String? subject;
  final DateTime at;
}

/// The whole picture: what is configured, what is calling, and what is failing.
class EeIdentityStatus {
  const EeIdentityStatus({
    required this.providers,
    required this.scimClients,
    required this.events,
    required this.totalMembers,
    required this.inactiveMembers,
    required this.linkedMembers,
  });

  factory EeIdentityStatus.fromJson(Map<String, dynamic> json) {
    final members = Map<String, dynamic>.from(
      json['members'] as Map? ?? const <String, dynamic>{},
    );
    return EeIdentityStatus(
      providers: (json['providers'] as List? ?? const [])
          .map((e) => EeIdentityProvider.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      scimClients: (json['scimClients'] as List? ?? const [])
          .map((e) => EeScimClient.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      events: (json['events'] as List? ?? const [])
          .map((e) => EeIdentityEvent.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      totalMembers: members['total'] as int? ?? 0,
      inactiveMembers: members['inactive'] as int? ?? 0,
      linkedMembers: members['linked'] as int? ?? 0,
    );
  }

  final List<EeIdentityProvider> providers;
  final List<EeScimClient> scimClients;
  final List<EeIdentityEvent> events;
  final int totalMembers;
  final int inactiveMembers;

  /// How many members a directory or provider actually vouches for. The number
  /// that says whether the integration is doing anything at all — zero linked
  /// members with a provider switched on is a working configuration that has
  /// never worked.
  final int linkedMembers;

  bool get quiet => events.isEmpty;
}
