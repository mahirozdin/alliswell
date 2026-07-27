import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/server_url.dart';

/// The address the app talks to is a user-facing setting because AllisWell is
/// self-hostable — and it is also what broke the first TestFlight build, which
/// shipped `http://localhost:3000` because nothing passed a --dart-define.
void main() {
  setUp(() => localKv.remove('alliswell_server_url'));

  group('normalizeServerUrl', () {
    test('accepts what people actually type', () {
      // Bare host → https, trailing slashes dropped, whitespace ignored.
      expect(normalizeServerUrl('api.example.com'), 'https://api.example.com');
      expect(
        normalizeServerUrl('  api.example.com/  '),
        'https://api.example.com',
      );
      expect(
        normalizeServerUrl('https://api.example.com///'),
        'https://api.example.com',
      );
      // A path is legitimate — an API can live under a prefix.
      expect(
        normalizeServerUrl('https://example.com/alliswell'),
        'https://example.com/alliswell',
      );
      // Plain http stays http: a self-hoster on a LAN has no certificate.
      expect(
        normalizeServerUrl('http://192.168.1.10:3000'),
        'http://192.168.1.10:3000',
      );
    });

    test('rejects what cannot be a server', () {
      expect(normalizeServerUrl(''), isNull);
      expect(normalizeServerUrl('   '), isNull);
      expect(normalizeServerUrl('ftp://example.com'), isNull);
      expect(normalizeServerUrl('https://'), isNull);
      // Query/fragment would be silently dropped when paths are appended.
      expect(normalizeServerUrl('https://example.com?x=1'), isNull);
    });
  });

  test('prettyServerUrl hides only the boring scheme', () {
    expect(
      prettyServerUrl('https://api.alliswell.space'),
      'api.alliswell.space',
    );
    expect(
      prettyServerUrl('https://example.com/alliswell'),
      'example.com/alliswell',
    );
    // http is worth showing — it tells the user the connection is not secure.
    expect(
      prettyServerUrl('http://192.168.1.10:3000'),
      'http://192.168.1.10:3000',
    );
  });

  group('resolution', () {
    test('falls back to the compiled default with no override', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(apiBaseUrlProvider), compiledApiBaseUrl);
      expect(container.read(usesCustomServerProvider), isFalse);
    });

    test('an override wins and is reported as custom', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(serverUrlOverrideProvider.notifier)
          .set('https://my.example.com');

      expect(container.read(apiBaseUrlProvider), 'https://my.example.com');
      expect(container.read(usesCustomServerProvider), isTrue);
    });

    test('clearing the override returns to the default', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(serverUrlOverrideProvider.notifier);
      await notifier.set('https://my.example.com');
      await notifier.set('');

      expect(container.read(apiBaseUrlProvider), compiledApiBaseUrl);
      expect(container.read(usesCustomServerProvider), isFalse);
    });

    test('the override survives a restart', () async {
      final first = ProviderContainer();
      await first
          .read(serverUrlOverrideProvider.notifier)
          .set('https://my.example.com');
      first.dispose();

      // A fresh container is what a relaunch looks like.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(serverUrlOverrideProvider); // triggers hydration
      await Future<void>.delayed(Duration.zero);
      expect(second.read(apiBaseUrlProvider), 'https://my.example.com');
    });
  });
}
