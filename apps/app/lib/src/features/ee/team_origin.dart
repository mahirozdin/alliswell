import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart' show apiBaseUrlProvider;
import 'providers.dart';

/// Team-aware sign-in (EE-018): which team this install is pointed at.
///
/// The team lives in the SERVER ADDRESS (`https://acme.example.com`), which
/// the app already persists and lets the user change — so team switching is
/// server switching, and nothing new needs storing. What the app cannot do is
/// tell a tenant host from an ordinary one on its own: `api.alliswell.space`
/// has the same shape as `acme.example.com`. The instance says which apex it
/// serves (`/ee/status` → `baseDomain`) and this derivation does the rest.
///
/// Deliberately identity-only for v1: the slug IS what the URL promises, so a
/// chip can be shown before any team endpoint exists. EE-021 replaces the
/// derived name with the team's real one; the colour rule stays.

@immutable
class AwTeamOrigin {
  const AwTeamOrigin({required this.slug, required this.displayName});

  final String slug;

  /// Derived from the slug until the server can be asked (EE-021):
  /// `acme-corp` → `Acme Corp`.
  final String displayName;

  /// The same FNV-1a over the same ten-colour palette the server uses for
  /// member profiles — one team, one colour, wherever it is drawn.
  Color get color => Color(_kTeamPalette[_fnv1a(slug) % _kTeamPalette.length]);

  @override
  bool operator ==(Object other) =>
      other is AwTeamOrigin &&
      other.slug == slug &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(slug, displayName);
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

extension _TrUpper on String {
  String toLocaleUpperCase() =>
      this == 'i' ? 'İ' : toUpperCase(); // Turkish dotted capital
}
