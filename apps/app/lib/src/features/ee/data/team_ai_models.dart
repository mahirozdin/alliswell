/// The team's AI credentials, client side (EE-111).
///
/// Like `EePortalLink`, this model is DELIBERATELY INCOMPLETE: there is no
/// field for the key and there cannot be one, because no response carries it.
/// The server keeps ciphertext and four characters; [keyLast4] is the whole of
/// what a screen may know.
///
/// The difference from the portal's link is worth stating, because it is the
/// one somebody will eventually argue with: that token was unrecoverable, so
/// omitting it was physics. This key IS recoverable from the ciphertext and is
/// still never sent, because an endpoint that can re-display a live credential
/// is a second place to lose one. A `String? apiKey` here would be the field
/// that invites somebody to add the endpoint.
class EeTeamAiConnection {
  const EeTeamAiConnection({
    required this.id,
    required this.provider,
    required this.status,
    this.keyLast4,
    this.baseUrl,
    this.defaultChatModel,
    this.defaultFastModel,
    this.lastUsedAt,
  });

  factory EeTeamAiConnection.fromJson(Map<String, dynamic> json) =>
      EeTeamAiConnection(
        id: json['id'] as String,
        provider: json['provider'] as String,
        status: EeTeamAiStatus.parse(json['status'] as String?),
        keyLast4: json['keyLast4'] as String?,
        baseUrl: json['baseUrl'] as String?,
        defaultChatModel: json['defaultChatModel'] as String?,
        defaultFastModel: json['defaultFastModel'] as String?,
        lastUsedAt: json['lastUsedAt'] == null
            ? null
            : DateTime.parse(json['lastUsedAt'] as String).toLocal(),
      );

  final String id;
  final String provider;
  final EeTeamAiStatus status;

  /// Four characters, or null for a provider reached by URL alone.
  final String? keyLast4;

  /// Where requests go — and, for a provider with regional endpoints, WHICH
  /// REGION processes the data (ADR-0014 §3).
  final String? baseUrl;

  final String? defaultChatModel;
  final String? defaultFastModel;
  final DateTime? lastUsedAt;
}

/// `error` means the provider refused the credential, so the screen can say
/// "this key stopped working" instead of every member discovering it one
/// failed request at a time.
enum EeTeamAiStatus {
  active,
  error;

  static EeTeamAiStatus parse(String? raw) =>
      raw == 'error' ? EeTeamAiStatus.error : EeTeamAiStatus.active;
}

/// The list AND the policy, in one object because they arrive in one response.
///
/// A screen that showed keys without showing whether members may bypass them
/// would be showing half a decision — so the server sends both and the model
/// keeps them together rather than letting a second provider drift apart from
/// the first.
class EeTeamAiData {
  const EeTeamAiData({
    required this.items,
    required this.personalKeysAllowed,
    required this.providers,
  });

  factory EeTeamAiData.fromJson(Map<String, dynamic> json) => EeTeamAiData(
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((e) => EeTeamAiConnection.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    personalKeysAllowed: (json['personalKeysAllowed'] as bool?) ?? true,
    // Derived from the server's adapter registry, not typed out here: a name
    // this screen offered but the server could not talk to would be storable,
    // sellable and broken at the first request.
    providers: ((json['providers'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toList(growable: false),
  );

  final List<EeTeamAiConnection> items;
  final bool personalKeysAllowed;
  final List<String> providers;
}
