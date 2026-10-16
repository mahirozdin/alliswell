import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/data/ai_attachment_loader.dart';
import 'package:alliswell/src/features/ai/data/ai_live_context.dart';
import 'package:alliswell/src/features/ai/data/ai_stream_client.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/search/search_recents.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_ai.dart';
import '../../support/sync_overrides.dart';

/// OPH-377 — "@" attachments end to end (LESSONS ai-mcp: code with no caller
/// is code believed to work): the real app, the real FAB, the real picker over
/// the replica, the real loader — only the byte fetch and the model stream are
/// canned. What reaches the request is asserted on the request itself.
late ProviderContainer _container;

const _sentinel = 'SENTINEL-KARAR-B';

class _World {
  _World(this.api, this.stream, this.fetched);
  final FakeApi api;
  final ScriptedAiStreamClient stream;
  final List<String> fetched;
  late final String noteId;
  late final String mdId;
  late final String pdfId;
  late final String bigId;
}

Future<_World> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await localKv.remove(kSearchRecentsKey);

  final api = FakeApi()..seedAiConnection(provider: 'anthropic');
  final stream = ScriptedAiStreamClient(script: const [AiTextDelta('Tamam')]);
  final fetched = <String>[];
  final world = _World(api, stream, fetched);
  world.noteId =
      api.seedNote(
            title: 'Q3 plan',
            contentMarkdown: 'Toplantıda $_sentinel seçildi.',
          )['id']
          as String;
  world.mdId =
      api.seedFile(
            name: 'notlar.md',
            targetType: 'workspace',
            targetId: api.workspaceId,
            mime: 'text/markdown',
            sizeBytes: 40,
          )['id']
          as String;
  world.pdfId =
      api.seedFile(
            name: 'deck.pdf',
            targetType: 'workspace',
            targetId: api.workspaceId,
            mime: 'application/pdf',
          )['id']
          as String;
  world.bigId =
      api.seedFile(
            name: 'uzun.txt',
            targetType: 'workspace',
            targetId: api.workspaceId,
            mime: 'text/plain',
            sizeBytes: 20000,
          )['id']
          as String;
  api.downloadUrls[world.mdId] = 'https://files.test/md?sig=SECRET';
  api.downloadUrls[world.bigId] = 'https://files.test/big?sig=SECRET';

  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  await tester.pumpWidget(
    ProviderScope(
      retry: awRetry,
      overrides: [
        ...syncTestOverrides(aiStreamClient: stream),
        secretStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(api.handle)),
        ),
        aiFileBytesFetcherProvider.overrideWithValue((url) async {
          fetched.add(url);
          if (url.contains('/big')) return utf8.encode('u' * 20000);
          return utf8.encode('# Notlar\n\nDosyadaki cümle.');
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          _container = ProviderScope.containerOf(context);
          return const AllisWellApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ai-fab')));
  await tester.pumpAndSettle();
  return world;
}

final _input = find.byKey(const Key('ai-input'));
final _panel = find.byKey(const Key('ai-mention-panel'));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_input, text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ai-send')));
  await tester.pumpAndSettle();
}

List<Map> _attached(ScriptedAiStreamClient stream, [int index = -1]) {
  final request = index < 0 ? stream.requests.last : stream.requests[index];
  final segments = (request.context?['segments'] as List? ?? const [])
      .cast<Map>();
  return segments.where((s) => s['tier'] == 'attached').toList();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_input).controller!.text;

void main() {
  testWidgets('typing "@" finds the note, Enter attaches it, the request '
      'carries its text, and later turns and a retry keep it', (tester) async {
    final w = await _pump(tester);

    await _type(tester, 'Özetle @Q3');
    expect(_panel, findsOneWidget);
    final row = find.byKey(Key('ai-mention-note-${w.noteId}'));
    expect(row, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('ai-attach-chip-${w.noteId}')), findsOneWidget);
    expect(_fieldText(tester), 'Özetle ');
    expect(_panel, findsNothing);

    await tester.enterText(_input, 'Özetle bunu');
    await tester.pump();
    final send = tester.widget<IconButton>(find.byKey(const Key('ai-send')));
    expect(send.onPressed, isNotNull);
    await _send(tester);

    final attached = _attached(w.stream);
    expect(attached, hasLength(1));
    expect(attached.single['id'], w.noteId);
    expect(attached.single['source'], 'attached_note');
    expect(attached.single['text'], contains(_sentinel));
    expect(find.byKey(const Key('ai-sent-attachment')), findsOneWidget);
    // The chip left the composer with the turn.
    expect(find.byKey(Key('ai-attach-chip-${w.noteId}')), findsNothing);

    // c — a second turn with no pick still carries the note…
    await tester.enterText(_input, 'peki bütçe');
    await tester.pump();
    await _send(tester);
    expect(_attached(w.stream).single['id'], w.noteId);
    expect(find.byKey(const Key('ai-sent-attachment')), findsOneWidget);

    // …and so does a retry after a failure.
    w.stream.script = const [AiStreamFailure('AI_UPSTREAM_ERROR', 'boom')];
    await tester.enterText(_input, 'bir daha');
    await tester.pump();
    await _send(tester);
    w.stream.script = const [AiTextDelta('oldu')];
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    expect(_attached(w.stream).single['id'], w.noteId);
    expect(w.stream.requests.length, 4);
  });

  testWidgets('a PDF row is disabled with the reason; a text file attaches '
      'as text and its URL never reaches the request', (tester) async {
    final w = await _pump(tester);

    await _type(tester, '@deck');
    final pdfRow = find.byKey(Key('ai-mention-file-${w.pdfId}'));
    expect(pdfRow, findsOneWidget);
    expect(
      find.text(
        'Only text files can be attached (PDF, images and Office files are '
        'not read)',
      ),
      findsOneWidget,
    );
    await tester.tap(pdfRow);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('ai-attach-chip-${w.pdfId}')), findsNothing);
    expect(_fieldText(tester), '@deck', reason: 'nothing was picked');

    await _type(tester, '@notlar');
    await tester.tap(find.byKey(Key('ai-mention-file-${w.mdId}')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('ai-attach-chip-${w.mdId}')), findsOneWidget);
    expect(w.fetched, ['https://files.test/md?sig=SECRET']);

    await tester.enterText(_input, 'ne yazıyor');
    await tester.pump();
    await _send(tester);
    final attached = _attached(w.stream).single;
    expect(attached['source'], 'attached_file');
    expect(attached['text'], contains('Dosyadaki cümle.'));
    final wire = jsonEncode(w.stream.requests.single.context);
    expect(wire, isNot(contains('files.test')));
    expect(wire, isNot(contains('SECRET')));
  });

  testWidgets('a long file shows "shortened" and the notice under the sent '
      'message; the model gets the first 12000 characters', (tester) async {
    final w = await _pump(tester);

    await _type(tester, '@uzun');
    await tester.tap(find.byKey(Key('ai-mention-file-${w.bigId}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('· shortened'), findsOneWidget);

    await tester.enterText(_input, 'özetle');
    await tester.pump();
    await _send(tester);
    final text = _attached(w.stream).single['text'] as String;
    expect(text, contains('[Truncated: the first 12000 of'));
    expect(find.byKey(const Key('ai-attach-notice')), findsOneWidget);
    expect(find.textContaining('Only the first 12,000 of'), findsOneWidget);
  });

  testWidgets('an e-mail never opens the panel; Esc closes it and the same '
      '"@" stays closed; removing a chip attaches nothing; no pick → no '
      'attached segment', (tester) async {
    final w = await _pump(tester);

    await _type(tester, 'ali@x.com yaz');
    expect(_panel, findsNothing);

    await _type(tester, 'bak @Q');
    expect(_panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(
      _input,
      findsOneWidget,
      reason: 'Esc closed the panel, not the sheet',
    );
    await _type(tester, 'bak @Q3');
    expect(_panel, findsNothing, reason: 'the same "@" stays dismissed');

    // The "@" button opens a fresh one.
    await _type(tester, 'bak');
    await tester.tap(find.byKey(const Key('ai-attach')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_fieldText(tester), 'bak @');
    expect(_panel, findsOneWidget);
    await tester.enterText(_input, 'bak @Q3');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('ai-mention-note-${w.noteId}')));
    await tester.pumpAndSettle();
    final chip = find.byKey(Key('ai-attach-chip-${w.noteId}'));
    expect(chip, findsOneWidget);
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.clear)),
    );
    await tester.pumpAndSettle();
    expect(chip, findsNothing);

    await tester.enterText(_input, 'merhaba');
    await tester.pump();
    await _send(tester);
    expect(_attached(w.stream), isEmpty);
    expect(find.byKey(const Key('ai-sent-attachment')), findsNothing);

    // The automatic bundle never holds a note (no change to T0–T2).
    final live = buildLiveAiContext(read: _container.read, query: 'Q3 plan');
    expect(
      live.segments.where(
        (s) => s.source.contains('note') || s.tier == 'attached',
      ),
      isEmpty,
    );
  });
}
