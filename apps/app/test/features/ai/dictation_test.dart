import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ai/ui/ai_bubble.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/fake_stt.dart';
import '../../support/sync_overrides.dart';

/// OPH-402 (U-07, U-14; A-66, A-07) — with AI on but no provider connected,
/// the microphone dictates into a quick-add field instead of opening a chat
/// that cannot answer. The capture rule is the Inbox bar's (ADR-0057 §3):
/// dateless → Inbox ("Fikirler"), dated → an open task.
Future<Widget> _app(FakeApi api, FakeSttController stt) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(stt: stt),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// AI is on for the server, but nobody has connected a provider.
FakeApi _noProvider() => FakeApi()..aiEnabled = true;

const _sheet = Key('dictation-sheet');
const _field = Key('dictation-field');
const _done = Key('dictation-done');

void main() {
  testWidgets('no provider: a tap dictates, and the words land in a quick '
      'add that saves a dateless task to the Inbox', (tester) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController()..initGate = Completer<void>();
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The dictation sheet, not the chat.
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.byType(AiBubble), findsNothing);

    // A-66: the OS prompt is up — say so instead of pretending to listen.
    expect(find.text('ai.voice.waitingPermission'.tr()), findsOneWidget);
    expect(find.text('ai.voice.listening'.tr()), findsNothing);

    stt.initGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('ai.voice.dictateTitle'.tr()), findsOneWidget);
    expect(find.text('ai.voice.waitingPermission'.tr()), findsNothing);
    expect(stt.calls.where((c) => c.startsWith('start:')), hasLength(1));

    stt.emitPartial('süt al');
    await tester.pump();
    expect(find.text('süt al'), findsOneWidget);

    // "Bitir" finishes; the transcript is editable before anything is saved.
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    expect(stt.calls, contains('stop'));
    final field = tester.widget<TextField>(
      find.descendant(of: find.byKey(_field), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, 'süt al');
    expect(api.tasks, isEmpty, reason: 'nothing is saved before the user taps');

    await tester.tap(find.byKey(const Key('quick-add-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(_sheet), findsNothing);
    expect(
      find.text('capture.addedInbox'.tr(args: {'title': 'süt al'})),
      findsOneWidget,
    );
    final saved = api.tasks.single;
    expect(saved['title'], 'süt al');
    expect(saved['status'], 'inbox');
    expect(api.aiExtractCalls, 0, reason: 'no provider, no model call');
  });

  testWidgets('a dictated date makes an open, dated task (ADR-0057 §3)', (
    tester,
  ) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController();
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    stt.emitFinal('tomorrow 9am call the bank');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-add-submit')));
    await tester.pumpAndSettle();

    final saved = api.tasks.single;
    expect(saved['title'], 'call the bank');
    expect(saved['status'], 'open');
    expect(saved['dueAt'], isNotNull);
  });

  testWidgets('press and hold dictates too; Cancel throws the words away', (
    tester,
  ) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController();
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    final fab = tester.getCenter(find.byKey(const Key('ai-fab')));
    final gesture = await tester.startGesture(fab);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.byType(AiBubble), findsNothing);
    expect(stt.calls.where((c) => c.startsWith('start:')), hasLength(1));
    await gesture.up();
    await tester.pumpAndSettle();

    stt.emitPartial('bunu kaydetme');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dictation-cancel')));
    await tester.pumpAndSettle();
    expect(stt.calls, contains('cancel'));
    expect(find.byKey(_sheet), findsNothing);
    expect(api.tasks, isEmpty);
  });

  testWidgets('no microphone here: the sheet is a quick add with the reason', (
    tester,
  ) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController(available: false);
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.text('ai.voice.denied'.tr()), findsOneWidget);
    expect(find.byKey(_field), findsOneWidget);

    await tester.enterText(
      find.descendant(of: find.byKey(_field), matching: find.byType(TextField)),
      'yazarak',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-submit')));
    await tester.pumpAndSettle();
    expect(api.tasks.single['status'], 'inbox');
  });

  testWidgets('R-10: no microphone on the device — says so, never listens', (
    tester,
  ) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController(noMicrophone: true);
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.text('ai.voice.noMicrophone'.tr()), findsOneWidget);
    expect(find.text('ai.voice.denied'.tr()), findsNothing);
    expect(find.byKey(_field), findsOneWidget);
    // The recognizer is never started: that is what aborts the app natively.
    expect(stt.calls.where((c) => c.startsWith('start')), isEmpty);
  });

  testWidgets('R-10: a recognizer that fails to start leaves a quick add', (
    tester,
  ) async {
    _phone(tester);
    final api = _noProvider();
    final stt = FakeSttController(
      startError: PlatformException(code: 'error_audio'),
    );
    await tester.pumpWidget(await _app(api, stt));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_field), findsOneWidget);
    expect(find.text('ai.voice.listening'.tr()), findsNothing);
  });

  test('R-10: the no-microphone line in both languages', () {
    String line(String code) {
      final json =
          jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
              as Map<String, dynamic>;
      return ((json['ai'] as Map)['voice'] as Map)['noMicrophone'] as String;
    }

    expect(
      line('tr'),
      'Bu cihazda mikrofon kullanılamıyor. Görevini yazarak ekleyebilirsin.',
    );
    expect(line('en'), startsWith('No microphone is available'));
  });

  testWidgets('the button says what it does: "add a task by voice"', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final api = _noProvider();
    await tester.pumpWidget(await _app(api, FakeSttController()));
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('ai.voice.dictateLabel'.tr()), findsOne);
    tester.semantics.tap(find.semantics.byLabel('ai.voice.dictateLabel'.tr()));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with a provider, the tap still opens the chat (unchanged)', (
    tester,
  ) async {
    _phone(tester);
    final api = FakeApi()..seedAiConnection(provider: 'anthropic');
    await tester.pumpWidget(await _app(api, FakeSttController()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(find.byKey(const Key('ai-input')), findsOneWidget);
  });

  group('A-07: the chat without a provider is not a dead end', () {
    Future<Widget> bubbleHost(FakeApi api, {FakeSttController? stt}) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemorySecretStore();
      await TokenStorage(store).save(fakeSession());
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAiBubble(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/settings/ai',
            builder: (_, _) => const Scaffold(body: Text('ai-settings-page')),
          ),
        ],
      );
      return ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(stt: stt ?? FakeSttController()),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: MaterialApp.router(
          theme: buildAwTheme(Brightness.light),
          routerConfig: router,
        ),
      );
    }

    testWidgets('two buttons, the new copy and the Inbox hint', (tester) async {
      final api = _noProvider();
      await tester.pumpWidget(await bubbleHost(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-unconfigured')), findsOneWidget);
      expect(find.text('ai.bubble.unconfiguredTitle'.tr()), findsOneWidget);
      expect(find.byKey(const Key('ai-connect-provider')), findsOneWidget);
      expect(find.byKey(const Key('ai-save-inbox')), findsOneWidget);
      final input = tester.widget<TextField>(find.byKey(const Key('ai-input')));
      expect(input.decoration!.hintText, 'ai.bubble.hintUnconfigured'.tr());

      // Nothing typed yet: "save" has nothing to save, so it waits.
      final save = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('ai-save-inbox')),
      );
      expect(save.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('ai-input')), 'fikir bu');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-save-inbox')));
      await tester.pumpAndSettle();
      expect(api.tasks.single['title'], 'fikir bu');
      expect(api.tasks.single['status'], 'inbox');
    });

    testWidgets('Enter saves to the Inbox instead of asking nobody', (
      tester,
    ) async {
      final api = _noProvider();
      await tester.pumpWidget(await bubbleHost(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('ai-input')), 'enterla');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(api.tasks.single['title'], 'enterla');
      expect(api.tasks.single['status'], 'inbox');
      expect(api.aiExtractCalls, 0);
    });

    testWidgets('"Connect a provider" opens the AI settings', (tester) async {
      final api = _noProvider();
      await tester.pumpWidget(await bubbleHost(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-connect-provider')));
      await tester.pumpAndSettle();
      expect(find.text('ai-settings-page'), findsOneWidget);
      expect(find.byType(AiBubble), findsNothing);
    });

    testWidgets('A-66 in the chat too: no "Listening…" behind the OS prompt', (
      tester,
    ) async {
      final api = FakeApi()..seedAiConnection(provider: 'anthropic');
      final stt = FakeSttController()..initGate = Completer<void>();
      await tester.pumpWidget(await bubbleHost(api, stt: stt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-mic')));
      await tester.pump();
      expect(find.text('ai.voice.waitingPermission'.tr()), findsOneWidget);
      expect(find.text('ai.voice.listening'.tr()), findsNothing);

      stt.initGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('ai.voice.listening'.tr()), findsOneWidget);
      expect(find.text('ai.voice.waitingPermission'.tr()), findsNothing);
    });
  });
}
