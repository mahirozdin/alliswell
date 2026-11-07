import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/server_url.dart';
import 'package:alliswell/src/features/ai/ui/mcp_connector_card.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-395 (E-28, A-77) — a connector URL on localhost is one Claude and
/// ChatGPT can never reach. A self-hoster behind a reverse proxy used to copy
/// it without a word; now the card says so, in the A-77 text.
Widget _card(String base) => ProviderScope(
  overrides: [apiBaseUrlProvider.overrideWithValue(base)],
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const Scaffold(body: McpConnectorCard()),
  ),
);

const _warning =
    'This address is only reachable from this machine. Set your public HTTPS '
    'URL in the server config.';

void main() {
  group('awIsLoopbackUrl', () {
    for (final url in const [
      'http://localhost:3000/mcp',
      'https://localhost/mcp',
      'http://127.0.0.1:3000/mcp',
      'http://127.10.0.2/mcp',
      'http://[::1]:3000/mcp',
      'http://0.0.0.0:3000/mcp',
      'http://api.localhost/mcp',
      'http://LOCALHOST:3000/mcp',
    ]) {
      test('$url is loopback', () => expect(awIsLoopbackUrl(url), isTrue));
    }
    for (final url in const [
      'https://api.example.com/mcp',
      'https://localhost.example.com/mcp',
      'http://192.168.1.10:3000/mcp',
      'not a url',
    ]) {
      test('$url is not', () => expect(awIsLoopbackUrl(url), isFalse));
    }
  });

  testWidgets('a localhost connector URL carries the A-77 warning', (
    tester,
  ) async {
    await tester.pumpWidget(_card('http://localhost:3000/api/v1'));
    await tester.pumpAndSettle();
    expect(find.text('http://localhost:3000/api/v1/mcp'), findsOneWidget);
    expect(find.byKey(const Key('ai-mcp-loopback-warning')), findsOneWidget);
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('a public HTTPS URL shows no warning', (tester) async {
    await tester.pumpWidget(_card('https://api.example.com/api/v1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-mcp-loopback-warning')), findsNothing);
  });
}
