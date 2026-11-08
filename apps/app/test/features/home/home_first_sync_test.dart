import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-394 (polish 2 R-06): on a cold first sync an account with 41 tasks
/// showed "No tasks yet / Add your first task" for about two seconds — the
/// replica was empty because nothing had been pulled yet, not because the
/// account was. Until the first pull of every workspace in scope has landed,
/// Home shows a loading skeleton; an empty state only once the replica KNOWS.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  final skeleton = find.byKey(const Key('home-first-sync-loading'));
  final firstRun = find.byKey(const Key('home-empty-first-run'));
  final done = find.byKey(const Key('home-empty-done'));

  /// Pumps the app with every `/sync/pull` held until [gate] completes.
  Future<void> pump(
    WidgetTester tester,
    FakeApi api,
    Completer<void> gate, {
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    Future<ResponseBody> handler(
      RequestOptions options,
      Map<String, dynamic>? body,
    ) async {
      if (options.uri.path == '/api/v1/sync/pull') await gate.future;
      return api.handle(options, body);
    }

    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(handler)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  FakeApi busyAccount() {
    final api = FakeApi();
    for (var i = 1; i <= 3; i++) {
      api.seedTask(title: 'Task $i');
    }
    return api;
  }

  testWidgets('phone: the skeleton holds Home until the first pull lands, '
      'then the tasks; "No tasks yet" never shows', (tester) async {
    final gate = Completer<void>();
    await pump(tester, busyAccount(), gate);

    expect(skeleton, findsOneWidget);
    expect(firstRun, findsNothing);
    expect(done, findsNothing);
    expect(find.bySemanticsLabel('Loading your tasks…'), findsOneWidget);

    // Still waiting a few seconds later: no empty state sneaks in.
    await tester.pump(const Duration(seconds: 5));
    expect(skeleton, findsOneWidget);
    expect(firstRun, findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(firstRun, findsNothing);
    expect(done, findsNothing);
    expect(find.text('Task 1'), findsOneWidget);
  });

  testWidgets('wide window: the same skeleton in the list pane', (
    tester,
  ) async {
    final gate = Completer<void>();
    await pump(tester, busyAccount(), gate, size: const Size(1440, 900));
    expect(skeleton, findsOneWidget);
    expect(firstRun, findsNothing);
    expect(done, findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(find.text('Task 1'), findsOneWidget);
  });

  testWidgets('a really empty account: skeleton first, "No tasks yet" once '
      'the pull says so', (tester) async {
    final gate = Completer<void>();
    await pump(tester, FakeApi(), gate);
    expect(skeleton, findsOneWidget);
    expect(firstRun, findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(firstRun, findsOneWidget);
  });

  testWidgets('a first pull that never answers gives way to the empty state '
      'after the wait, never an endless skeleton', (tester) async {
    final gate = Completer<void>();
    await pump(tester, FakeApi(), gate);
    expect(skeleton, findsOneWidget);
    await tester.pump(kFirstPullWait + const Duration(seconds: 1));
    await tester.pump();
    expect(skeleton, findsNothing);
    expect(firstRun, findsOneWidget);
  });

  testWidgets('Turkish label (A-12)', (tester) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    expect('home.firstSyncLoading'.tr(), 'Görevlerin getiriliyor…');
  });
}
