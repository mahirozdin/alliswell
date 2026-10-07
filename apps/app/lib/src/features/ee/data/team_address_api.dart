import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// A team endpoint answered 404 (OPH-356, UI-AUDIT #7).
///
/// On a server that serves a base domain, every `/ee/team/*` endpoint answers
/// only on the team's own address (`acme.example.com`, ADR-0004); asked on the
/// service's own address it is a 404, and so is a team host for somebody who
/// is not in that team. Neither is "nothing here": the list a screen would
/// have drawn empty is a list the server never read. So the clients that used
/// to turn this into `[]` or `null` throw it instead, typed, and the screen
/// decides — "your team's address is needed" where the app is not on one,
/// "not in this team" where it is.
class EeNoTeamHereException extends ApiException {
  const EeNoTeamHereException()
    : super('EE_NO_TEAM_HERE', 'No team answers at this address');
}

/// Throws [EeNoTeamHereException] for a 404, [ApiException] for the rest.
Never throwTeamError(DioException e) {
  if (e.response?.statusCode == 404) throw const EeNoTeamHereException();
  throw asApiException(e);
}

/// The signed-in person's team, as `GET /api/v1/ee/me/team` tells it on ANY
/// address of the instance (EE-300, ADR-0021 §5). A hint, not a context: the
/// team's endpoints still answer only on [origin].
class EeMyTeam {
  const EeMyTeam({
    required this.slug,
    required this.name,
    this.color,
    this.origin,
  });

  factory EeMyTeam.fromJson(Map<String, dynamic> json) => EeMyTeam(
    slug: (json['slug'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    color: json['color'] as String?,
    origin: json['origin'] as String?,
  );

  final String slug;
  final String name;

  /// `#RRGGBB`, when the server says.
  final String? color;

  /// `https://<slug>.<baseDomain>`; null on a single-origin install, where
  /// there is no other address to go to.
  final String? origin;
}

/// What an invitation link says before anything is redeemed
/// (`GET /api/v1/ee/invites/:token`, EE-039): which team, which address, and
/// whether that address already has an account.
class EeInvitePreview {
  const EeInvitePreview({
    required this.email,
    this.teamName,
    this.teamSlug,
    this.accountExists = false,
  });

  factory EeInvitePreview.fromJson(Map<String, dynamic> json) =>
      EeInvitePreview(
        email: (json['email'] as String?) ?? '',
        teamName: json['teamName'] as String?,
        teamSlug: json['teamSlug'] as String?,
        accountExists: json['accountExists'] == true,
      );

  final String email;
  final String? teamName;
  final String? teamSlug;
  final bool accountExists;
}

/// What a redeemed invitation produced: `created` → sign in with the password
/// just chosen; `existing` → the session that redeemed it is already the one.
class EeInviteAccepted {
  const EeInviteAccepted({required this.account, required this.email});

  factory EeInviteAccepted.fromJson(Map<String, dynamic> json) =>
      EeInviteAccepted(
        account: (json['account'] as String?) ?? 'existing',
        email: (json['email'] as String?) ?? '',
      );

  final String account;
  final String email;

  bool get created => account == 'created';
}

/// `/ee/me/team` on the address the app is signed in to.
class EeTeamAddressApi {
  const EeTeamAddressApi(this._dio);
  final Dio _dio;

  /// Null for "no hint": the account has no team (`TEAM_NONE`), or the route
  /// is not there (no `teams` entitlement, a server from before EE-300).
  Future<EeMyTeam?> myTeam() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/v1/ee/me/team');
      final team = EeMyTeam.fromJson(res.data ?? const {});
      return team.slug.isEmpty ? null : team;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw asApiException(e);
    }
  }
}

/// The invitation endpoints, on the TEAM's address (EE-039).
///
/// The [Dio] here deliberately carries no refresh interceptor: a wrong code
/// answers 401 (`INVITE_CODE_WRONG`), and a client that took that for an
/// expired session would refresh and send the same code again — spending a
/// second of the invitation's five attempts on one tap.
class EeInviteApi {
  const EeInviteApi(this._dio, {this.accessToken});
  final Dio _dio;

  /// Sent when somebody is signed in — the endpoint accepts both callers.
  final String? accessToken;

  Options get _options => Options(
    headers: {if (accessToken != null) 'Authorization': 'Bearer $accessToken'},
  );

  Future<EeInvitePreview> preview(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/invites/${Uri.encodeComponent(token)}',
      );
      return EeInvitePreview.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<EeInviteAccepted> accept(
    String token, {
    required String code,
    String? password,
    String? displayName,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/invites/${Uri.encodeComponent(token)}/accept',
        data: {
          'code': code,
          if (password != null && password.isNotEmpty) 'password': password,
          if (displayName != null && displayName.trim().isNotEmpty)
            'displayName': displayName.trim(),
        },
        options: _options,
      );
      return EeInviteAccepted.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
