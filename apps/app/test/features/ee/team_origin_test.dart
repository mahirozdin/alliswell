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
}
