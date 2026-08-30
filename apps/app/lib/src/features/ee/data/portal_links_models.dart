/// Public request links, client side (EE-106).
///
/// The model that matters here is the one that is DELIBERATELY INCOMPLETE:
/// `EePortalLink` has no token and no URL. The server keeps only a keyed
/// digest of the token, so there is nothing to send — and a field that could
/// hold one would be a field somebody eventually caches.
///
/// The URL exists exactly once, in [EePortalLinkCreated], as the answer to a
/// create. Modelling it as a separate type rather than a nullable field on the
/// link is the point: a `String?` invites `link.url ?? ''` at a call site, and
/// then a list of links renders a column of empty strings where a secret used
/// to be. Two types cannot be confused.
class EePortalLink {
  const EePortalLink({
    required this.id,
    required this.serviceId,
    required this.state,
    required this.enabled,
    required this.expiresAt,
    this.unitId,
    this.revokedAt,
    this.createdAt,
    this.origin,
    this.hasCustomFields = false,
  });

  factory EePortalLink.fromJson(Map<String, dynamic> json) => EePortalLink(
    id: json['id'] as String,
    serviceId: json['serviceId'] as String,
    unitId: json['unitId'] as String?,
    state: EePortalLinkState.parse(json['state'] as String?),
    enabled: (json['enabled'] as bool?) ?? true,
    expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
    revokedAt: json['revokedAt'] == null
        ? null
        : DateTime.parse(json['revokedAt'] as String).toLocal(),
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String).toLocal(),
    origin: json['origin'] as String?,
    hasCustomFields: (json['hasCustomFields'] as bool?) ?? false,
  );

  final String id;
  final String serviceId;

  /// Which desk it reaches. Set even when the service routes to one unit —
  /// the server resolves it at creation so a screen never shows an empty
  /// destination for a link that has one (ADR-0013 §3).
  final String? unitId;

  final EePortalLinkState state;

  /// The reversible switch, kept beside [state] because they answer different
  /// questions: `enabled` is what the toggle shows, `state` is what the badge
  /// says. A link can be enabled and still expired.
  final bool enabled;

  final DateTime expiresAt;
  final DateTime? revokedAt;
  final DateTime? createdAt;

  /// The host the form lives on — enough to say "this one is the workshop's"
  /// without being enough to open it.
  final String? origin;

  final bool hasCustomFields;

  bool get isLive => state == EePortalLinkState.active;
}

/// The four states a link can be in, and the order revocation wins in.
enum EePortalLinkState {
  active,
  disabled,
  expired,
  revoked;

  static EePortalLinkState parse(String? raw) => switch (raw) {
    'active' => EePortalLinkState.active,
    'disabled' => EePortalLinkState.disabled,
    'expired' => EePortalLinkState.expired,
    'revoked' => EePortalLinkState.revoked,
    // An unknown state from a newer server reads as revoked rather than
    // active: the safe misreading of "I do not know what this is" on a door
    // to the public is "assume it is shut".
    _ => EePortalLinkState.revoked,
  };

  /// Whether anything can still be done to it. Revocation is permanent, so a
  /// revoked link's controls are gone rather than disabled-looking.
  bool get isEditable => this != EePortalLinkState.revoked;
}

/// A ceiling and what has been spent against it.
class EePortalQuota {
  const EePortalQuota({
    required this.used,
    this.max,
    this.remaining,
    this.canAdd = true,
  });

  factory EePortalQuota.fromJson(Map<String, dynamic>? json) => EePortalQuota(
    used: (json?['used'] as int?) ?? 0,
    max: json?['max'] as int?,
    remaining: json?['remaining'] as int?,
    canAdd: (json?['canAdd'] as bool?) ?? true,
  );

  final int used;

  /// `null` means UNLIMITED, not zero. The distinction is the whole reason
  /// this is nullable: a plan with no ceiling must not render as a plan with
  /// a ceiling of nothing (EE-029's stance, and EE-102 re-proved it).
  final int? max;

  final int? remaining;
  final bool canAdd;

  bool get isUnlimited => max == null;
}

/// Everything the screen needs, in one shape.
class EePortalLinksData {
  const EePortalLinksData({
    required this.links,
    required this.linkQuota,
    required this.ticketQuota,
  });

  factory EePortalLinksData.fromJson(Map<String, dynamic> json) =>
      EePortalLinksData(
        links: ((json['links'] as List?) ?? const [])
            .map((l) => EePortalLink.fromJson(l as Map<String, dynamic>))
            .toList(),
        linkQuota: EePortalQuota.fromJson(
          (json['quota'] as Map<String, dynamic>?)?['links']
              as Map<String, dynamic>?,
        ),
        ticketQuota: EePortalQuota.fromJson(
          (json['quota'] as Map<String, dynamic>?)?['ticketsThisMonth']
              as Map<String, dynamic>?,
        ),
      );

  final List<EePortalLink> links;
  final EePortalQuota linkQuota;
  final EePortalQuota ticketQuota;
}

/// The answer to a create — and the ONLY place a usable URL exists.
///
/// See the file header for why this is its own type. The screen shows [url]
/// once, in a dialog the person must dismiss, and can never get it back.
class EePortalLinkCreated {
  const EePortalLinkCreated({required this.link, required this.url});

  factory EePortalLinkCreated.fromJson(Map<String, dynamic> json) =>
      EePortalLinkCreated(
        link: EePortalLink.fromJson(json['link'] as Map<String, dynamic>),
        url: json['url'] as String,
      );

  final EePortalLink link;
  final String url;
}
