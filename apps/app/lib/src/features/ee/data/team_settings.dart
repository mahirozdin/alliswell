/// The team's own settings (EE-037) — the client mirror of
/// `GET /api/v1/ee/team/settings`.
///
/// Every optional field means NOT CHOSEN, never "the default". A team that
/// never opened this screen must render exactly as it did before the feature
/// existed: the colour derived from its slug, the viewer's own language, and
/// no logo. Turning a null into a default here would quietly make every team
/// look like it had made a choice.
class EeTeamSettings {
  const EeTeamSettings({
    required this.name,
    required this.slug,
    this.locale,
    this.timezone,
    this.colorRgb,
    this.logoUrl,
    this.hasLogo = false,
  });

  final String name;

  /// The subdomain. Read-only here — a slug is never reused (server-side
  /// ledger), so renaming a team does not rename its host.
  final String slug;

  /// `en` | `tr`, or null to follow each viewer's own choice.
  final String? locale;

  /// An IANA zone id. Null means UTC for anything that computes with it.
  final String? timezone;

  /// `#RRGGBB`, or null for the colour the app derives from the slug.
  final String? colorRgb;

  /// An EXPIRING url minted per read — never persist it, never cache it past
  /// the screen that asked for it.
  final String? logoUrl;

  /// Whether a logo is stored at all. Distinct from [logoUrl], which is also
  /// null when this server has no object storage configured — "no logo" and
  /// "cannot show you the logo" are different truths.
  final bool hasLogo;

  factory EeTeamSettings.fromJson(Map<String, dynamic> json) => EeTeamSettings(
    name: (json['name'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    locale: json['locale'] as String?,
    timezone: json['timezone'] as String?,
    colorRgb: json['colorRgb'] as String?,
    logoUrl: json['logoUrl'] as String?,
    hasLogo: json['hasLogo'] as bool? ?? false,
  );

  EeTeamSettings copyWith({
    String? name,
    String? locale,
    String? timezone,
    String? colorRgb,
  }) => EeTeamSettings(
    name: name ?? this.name,
    slug: slug,
    locale: locale ?? this.locale,
    timezone: timezone ?? this.timezone,
    colorRgb: colorRgb ?? this.colorRgb,
    logoUrl: logoUrl,
    hasLogo: hasLogo,
  );
}
