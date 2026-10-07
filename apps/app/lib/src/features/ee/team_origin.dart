import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/kv/local_kv.dart';
import '../../core/server_url.dart';
import '../../sections.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart' show currentUserIdProvider;
import 'assignments_providers.dart' show workspaceRosterProvider;
import 'data/team_address_api.dart';
import 'providers.dart';
import 'team_admin_providers.dart' show eeTeamProvider;

/// Team-aware sign-in (EE-018): which team this install is pointed at.
///
/// The team lives in the SERVER ADDRESS (`https://acme.example.com`), which
/// the app already persists and lets the user change — so team switching is
/// server switching, and nothing new needs storing. What the app cannot do is
/// tell a tenant host from an ordinary one on its own: `api.alliswell.space`
/// has the same shape as `acme.example.com`. The instance says which apex it
/// serves (`/ee/status` → `baseDomain`) and this derivation does the rest.
///
/// Deliberately identity-only: the slug IS what the URL promises, so a chip
/// can be shown before any team endpoint answers. The team's real name comes
/// from its own record ([teamIdentityProvider], OPH-356); the colour rule
/// stays the server's.

@immutable
class AwTeamOrigin {
  const AwTeamOrigin({
    required this.slug,
    required this.displayName,
    this.colorOverride,
  });

  final String slug;

  /// Derived from the slug — `acme-corp` → `Acme Corp` — until the team's own
  /// record answers ([teamIdentityProvider]); then the team's real name.
  final String displayName;

  /// The colour the team chose for itself, when the server has said
  /// (`/ee/me/team` → `color`); otherwise [color] derives it.
  final Color? colorOverride;

  /// The same FNV-1a over the same ten-colour palette the server uses for
  /// member profiles — one team, one colour, wherever it is drawn — unless
  /// the team picked its own.
  Color get color =>
      colorOverride ??
      Color(_kTeamPalette[_fnv1a(slug) % _kTeamPalette.length]);

  AwTeamOrigin withIdentity({required String name, Color? color}) =>
      AwTeamOrigin(
        slug: slug,
        displayName: name,
        colorOverride: color ?? colorOverride,
      );

  @override
  bool operator ==(Object other) =>
      other is AwTeamOrigin &&
      other.slug == slug &&
      other.displayName == displayName &&
      other.colorOverride == colorOverride;

  @override
  int get hashCode => Object.hash(slug, displayName, colorOverride);
}

const List<int> _kTeamPalette = [
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFDC2626,
  0xFFEA580C,
  0xFFCA8A04,
  0xFF16A34A,
  0xFF0D9488,
  0xFF0284C7,
  0xFF4F46E5,
];

int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Reserved labels never name a team — the server refuses to hand them out,
/// so the app must not draw a chip for `www.example.com` either.
const Set<String> _kReservedLabels = {
  'admin',
  'api',
  'app',
  'assets',
  'billing',
  'cdn',
  'demo',
  'dev',
  'docs',
  'ftp',
  'help',
  'imap',
  'login',
  'mail',
  'ns1',
  'ns2',
  'portal',
  'smtp',
  'staging',
  'static',
  'status',
  'support',
  'test',
  'www',
};

final RegExp _kLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])$');

/// Pure: the team a server URL points at, or null. Mirrors the server's own
/// host rules (one extra label, DNS-strict, no reserved names, no `--`).
AwTeamOrigin? teamOriginOf(String serverUrl, String? baseDomain) {
  if (baseDomain == null || baseDomain.isEmpty) return null;
  final host = Uri.tryParse(serverUrl)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;

  final apex = baseDomain.toLowerCase();
  final suffix = '.$apex';
  if (!host.endsWith(suffix)) return null;
  final label = host.substring(0, host.length - suffix.length);
  if (label.isEmpty || label.contains('.')) return null;
  if (!_kLabel.hasMatch(label) || label.contains('--')) return null;
  if (_kReservedLabels.contains(label)) return null;

  return AwTeamOrigin(slug: label, displayName: _titleize(label));
}

String _titleize(String slug) => slug
    .split('-')
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toLocaleUpperCase() + part.substring(1))
    .join(' ');

/// The team this install is signed in to, or null on a plain / CE server.
/// Rebuilds when the server address changes — switching teams is one setting.
final teamOriginProvider = Provider<AwTeamOrigin?>((ref) {
  final status = ref.watch(eeStatusProvider).value;
  if (status == null || !status.has('teams')) return null;
  return teamOriginOf(ref.watch(apiBaseUrlProvider), status.baseDomain);
});

/// The team as a person should read it (OPH-356, UI-AUDIT #84): the name its
/// own record carries (`GET /ee/team`), the slug's titleized form only until
/// that answers or when it cannot (offline, not a member). A chip that said
/// "Demo Fabrika" beside a switcher saying "Demir Çelik Fabrikası" was two
/// names for one company on every screen.
final teamIdentityProvider = Provider<AwTeamOrigin?>((ref) {
  final origin = ref.watch(teamOriginProvider);
  if (origin == null) return null;
  // `/ee/me/team` first: it carries the colour the team chose, and answers
  // for every member. `/ee/team` is the fallback for a server from before it.
  final mine = ref.watch(eeMyTeamProvider).value;
  if (mine != null && mine.slug == origin.slug && mine.name.trim().isNotEmpty) {
    return origin.withIdentity(
      name: mine.name.trim(),
      color: parseTeamColor(mine.color),
    );
  }
  final team = ref.watch(eeTeamProvider).value;
  if (team == null || team.slug != origin.slug || team.name.trim().isEmpty) {
    return origin;
  }
  return origin.withIdentity(name: team.name.trim());
});

/// `#RRGGBB` → a colour, or null for anything else.
Color? parseTeamColor(String? hex) {
  if (hex == null) return null;
  final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

// ── The team's address (OPH-356, ADR-0021) ─────────────────────────────────

/// Which apex domains a `?server=` in an invitation link may hang off.
///
/// Signed in, the instance SAYS which one it serves (`/ee/status` →
/// `baseDomain`) and that answer is the only one. Signed out there is nobody
/// to ask — `/ee/status` wants a session — so the trust is anchored where the
/// app already is: the address it is pointed at, and that host's parent
/// (`api.example.com` → `example.com`). Either way a link can only move the
/// app to a sibling of the server it was already talking to, never to a host
/// somebody typed into an e-mail.
Set<String> trustedTeamApexes(String serverUrl, {String? baseDomain}) {
  if (baseDomain != null && baseDomain.isNotEmpty) {
    return {baseDomain.toLowerCase()};
  }
  final host = Uri.tryParse(serverUrl)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return const {};
  final labels = host.split('.');
  return {
    host,
    // `api.example.com` → `example.com`; never a bare TLD.
    if (labels.length >= 3) labels.sublist(1).join('.'),
  };
}

/// A `?server=` value, checked (ADR-0021 §4): https, an origin and nothing
/// more, and a team host — one non-reserved label — under one of [apexes].
/// Returns the normalised origin, or null when the link does not belong here.
({String origin, AwTeamOrigin team})? acceptJoinServer(
  String raw,
  Set<String> apexes,
) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  for (final apex in apexes) {
    final team = teamOriginOf(raw.trim(), apex);
    if (team != null) {
      final origin = uri.hasPort
          ? 'https://${uri.host.toLowerCase()}:${uri.port}'
          : 'https://${uri.host.toLowerCase()}';
      return (origin: origin, team: team);
    }
  }
  return null;
}

final eeTeamAddressApiProvider = Provider<EeTeamAddressApi>(
  (ref) => EeTeamAddressApi(ref.watch(apiClientProvider)),
);

/// The person's team, asked where it can matter: the instance has teams and
/// serves a base domain. Off a team host it is the hint ("your team lives at
/// X"); on one it is the team's own name and colour for the chip. Null for
/// "nothing to say" — no team, no endpoint (an older server), no answer.
final eeMyTeamProvider = FutureProvider<EeMyTeam?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  final status = ref.watch(eeStatusProvider).value;
  if (status == null || !status.has('teams')) return null;
  final base = status.baseDomain;
  if (base == null || base.isEmpty) return null;
  try {
    return await ref.watch(eeTeamAddressApiProvider).myTeam();
  } catch (_) {
    return null;
  }
});

/// Where the person's team lives, when the app is somewhere else: the
/// origin [eeMyTeamProvider] names, or null.
final eeTeamAddressHintProvider = Provider<EeMyTeam?>((ref) {
  if (ref.watch(teamOriginProvider) != null) return null;
  final team = ref.watch(eeMyTeamProvider).value;
  final origin = team?.origin;
  if (team == null || origin == null || origin.isEmpty) return null;
  if (origin == ref.watch(apiBaseUrlProvider)) return null;
  return team;
});

/// Should a team surface say "your team's address is needed" instead of
/// asking the server (UI-AUDIT #7)?
///
/// Every team endpoint answers only on the team's own host (ADR-0004), so on
/// the service's own address they are all 404 — which the screens used to
/// draw as "nothing waiting", "you have not asked for anything", "you may
/// not". True when the instance has teams AND serves a base domain (a
/// single-origin install resolves its team without one), the app is not on a
/// team host, and this person is in a team: the server says so, or the
/// replica already holds a team workspace's roster.
final eeTeamAddressRequiredProvider = Provider<bool>((ref) {
  final status = ref.watch(eeStatusProvider).value;
  if (status == null || !status.has('teams')) return false;
  final base = status.baseDomain;
  if (base == null || base.isEmpty) return false;
  if (ref.watch(teamOriginProvider) != null) return false;
  if (ref.watch(eeTeamAddressHintProvider) != null) return true;
  return ref.watch(workspaceRosterProvider).value?.isNotEmpty ?? false;
});

/// Points the app at a team's own address WITHOUT signing out.
///
/// The server sheet signs out on a change because a token from one server
/// means nothing to another. A team host is not another server: it is the
/// same instance under its own base domain (the only hosts this is ever
/// called with — [acceptJoinServer] and `/ee/me/team` produce nothing else),
/// so the session and the replica stay the person's. Everything that talks to
/// the server rebuilds on the address; the instance answers are asked again.
///
/// From Home, and only from there: with [router] the app goes Home first and
/// waits for the pages leaving to finish leaving. A screen that is covered
/// (the shell under a pushed page, an offstage tab) has its providers paused,
/// and the first build after the address moved would rebuild them inside
/// that build — which Flutter refuses. On a visible Home they rebuild as the
/// address moves, outside any build.
///
/// Takes the CONTAINER rather than a widget's ref: the screen that asks is
/// usually gone by the time the address moves.
Future<void> switchToTeamOrigin(
  ProviderContainer container,
  String origin, {
  GoRouter? router,
}) async {
  if (router != null) {
    router.go(AppSection.home.path);
    final binding = WidgetsBinding.instance;
    // Bounded: a screen with a perpetual animation does not hold this up.
    for (var frame = 0; frame < 120; frame++) {
      await binding.endOfFrame;
      if (frame >= 1 && !binding.hasScheduledFrame) break;
    }
  }
  await container
      .read(serverUrlOverrideProvider.notifier)
      .set(origin == compiledApiBaseUrl ? '' : origin);
  container.invalidate(eeStatusProvider);
  container.invalidate(eePermissionsProvider);
}

/// The invitation endpoints on [origin] — unauthenticated by construction
/// (see [EeInviteApi] for why there is no refresh here). A family so a test
/// can hand back a fake per address.
final eeInviteDioProvider = Provider.family<Dio, String>(
  (ref, origin) => Dio(BaseOptions(baseUrl: origin)),
);

/// The invitation client for [origin], carrying the session's access token
/// as it is NOW (it rotates; a provider would hold yesterday's).
EeInviteApi eeInviteApiFor(WidgetRef ref, String origin) => EeInviteApi(
  ref.read(eeInviteDioProvider(origin)),
  accessToken: ref.read(authRepositoryProvider).accessToken,
);

/// "Not now" on the team-address suggestion, per person and per address, so
/// somebody who works on the service's own address on purpose is told once.
const String kTeamHintDismissedPrefix = 'alliswell_team_hint_dismissed::';

final eeTeamHintDismissedProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final hint = ref.watch(eeTeamAddressHintProvider);
  if (userId == null || hint?.origin == null) return false;
  return await localKv.get(
        '$kTeamHintDismissedPrefix$userId::${hint!.origin}',
      ) ==
      'true';
});

Future<void> dismissTeamHint(WidgetRef ref) async {
  final userId = ref.read(currentUserIdProvider);
  final origin = ref.read(eeTeamAddressHintProvider)?.origin;
  if (userId == null || origin == null) return;
  await localKv.set('$kTeamHintDismissedPrefix$userId::$origin', 'true');
  ref.invalidate(eeTeamHintDismissedProvider);
}

extension _TrUpper on String {
  String toLocaleUpperCase() =>
      this == 'i' ? 'İ' : toUpperCase(); // Turkish dotted capital
}
