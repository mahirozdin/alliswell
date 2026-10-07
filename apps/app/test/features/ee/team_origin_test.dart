import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/team_origin.dart';

/// EE-018 — the pure half: which server address means which team. The rules
/// mirror the server's host resolution, so the app never draws a team chip
/// for a host the server would refuse to resolve.
void main() {
  const base = 'example.com';

  group('teamOriginOf', () {
    test('one extra label is a team', () {
      expect(teamOriginOf('https://acme.example.com', base)?.slug, 'acme');
      expect(teamOriginOf('https://acme.example.com:8443', base)?.slug, 'acme');
      expect(teamOriginOf('https://ACME.Example.COM', base)?.slug, 'acme');
    });

    test('the display name is titleized from the slug until EE-021', () {
      expect(
        teamOriginOf('https://acme.example.com', base)?.displayName,
        'Acme',
      );
      expect(
        teamOriginOf('https://acme-corp.example.com', base)?.displayName,
        'Acme Corp',
      );
      // Turkish dotted capital — 'izmir' must not become 'Izmir'.
      expect(
        teamOriginOf('https://izmir.example.com', base)?.displayName,
        'İzmir',
      );
    });

    test('apex, deeper, reserved and foreign hosts are not teams', () {
      expect(teamOriginOf('https://example.com', base), isNull);
      expect(teamOriginOf('https://a.b.example.com', base), isNull);
      expect(teamOriginOf('https://www.example.com', base), isNull);
      expect(teamOriginOf('https://api.example.com', base), isNull);
      expect(teamOriginOf('https://evil.com', base), isNull);
      expect(teamOriginOf('https://evil-example.com', base), isNull);
      expect(teamOriginOf('https://xn--acme.example.com', base), isNull);
      expect(teamOriginOf('https://x.example.com', base), isNull); // 1 char
    });

    test('without a baseDomain nothing is a team — the app never guesses', () {
      // This is what keeps `api.alliswell.space` from rendering as a tenant.
      expect(teamOriginOf('https://api.alliswell.space', null), isNull);
      expect(teamOriginOf('https://acme.example.com', ''), isNull);
      expect(teamOriginOf('not a url', base), isNull);
    });

    test('colour is stable per slug and equality is by value', () {
      final a = teamOriginOf('https://acme.example.com', base)!;
      final b = teamOriginOf('https://acme.example.com:9000', base)!;
      expect(a, equals(b));
      expect(a.color, equals(b.color));
      expect(
        teamOriginOf('https://globex.example.com', base)!.color,
        isNot(equals(a.color)),
      );
    });
  });

  // OPH-356, ADR-0021 §4 — the link may move the app, so the rule is pinned.
  group('UI-AUDIT #5: which apex a join link may hang off', () {
    test('signed in, the instance\'s own baseDomain is the only answer', () {
      expect(
        trustedTeamApexes('https://api.example.com', baseDomain: 'Example.com'),
        {'example.com'},
      );
    });

    test('signed out, the server the app is on and its parent', () {
      expect(trustedTeamApexes('https://api.alliswell.space'), {
        'api.alliswell.space',
        'alliswell.space',
      });
      // A two-label host never yields a bare TLD.
      expect(trustedTeamApexes('https://example.com'), {'example.com'});
      expect(trustedTeamApexes('not a url'), isEmpty);
    });
  });

  group('UI-AUDIT #5: acceptJoinServer', () {
    final apexes = {'api.example.com', 'example.com'};

    test('an https team host of the trusted apex is accepted, normalised', () {
      final ok = acceptJoinServer('https://Acme.Example.com', apexes)!;
      expect(ok.origin, 'https://acme.example.com');
      expect(ok.team.slug, 'acme');
      expect(
        acceptJoinServer('https://acme.example.com:8443/', apexes)!.origin,
        'https://acme.example.com:8443',
      );
    });

    test('anything else is refused — never silently followed', () {
      for (final raw in [
        'http://acme.example.com', // not https
        'https://evil.com', // foreign
        'https://acme.evil.com',
        'https://example.com', // the apex itself
        'https://api.example.com', // reserved label
        'https://www.example.com',
        'https://a.b.example.com', // two labels deep
        'https://acme.example.com/steal', // a path
        'https://acme.example.com?x=1', // a query
        'https://user@acme.example.com', // credentials
        'javascript:alert(1)',
        '',
      ]) {
        expect(acceptJoinServer(raw, apexes), isNull, reason: raw);
      }
    });
  });

  test('UI-AUDIT #84: a team colour is read from #RRGGBB or not at all', () {
    expect(parseTeamColor('#16A34A'), const Color(0xFF16A34A));
    expect(parseTeamColor('16a34a'), const Color(0xFF16A34A));
    expect(parseTeamColor('green'), isNull);
    expect(parseTeamColor(null), isNull);
    final acme = teamOriginOf('https://acme.example.com', 'example.com')!;
    final named = acme.withIdentity(
      name: 'Demir Çelik Fabrikası',
      color: const Color(0xFF16A34A),
    );
    expect(named.displayName, 'Demir Çelik Fabrikası');
    expect(named.color, const Color(0xFF16A34A));
    expect(named.slug, 'acme');
  });
}
