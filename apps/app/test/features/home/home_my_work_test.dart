import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../../support/sync_overrides.dart';

const _own = '01WSOWNAAAAAAAAAAAAAAAAAAA';
const _unitA = '01WSUNITAAAAAAAAAAAAAAAAAA';
const _unitB = '01WSUNITBBBBBBBBBBBBBBBBBB';
const _me = 'user-1';
const _colleague = '01USERCOLLEAGUEAAAAAAAAAAA';

String _id(String prefix) => prefix.padRight(26, '0');

/// A server with one person in an organisation: the workspace their account
/// owns (which only ever carries unsent drafts) and two of the organisation's
/// units, each pulled on its own.
class _TeamApi {
  final Map<String, List<Map<String, dynamic>>> rows = {
    _own: [],
    _unitA: [],
    _unitB: [],
  };
  final List<Map<String, dynamic>> pushed = [];
  final Set<String> pulled = {};
  int revision = 1;

  void task(
    String id,
    String unit,
    String title, {
    required String createdBy,
    List<String> on = const [],
  }) {
    rows[unit]!.add({
      'revision': revision,
      'entityType': 'task',
      'entityId': _id(id),
      'operation': 'update',
      'data': {
        'id': _id(id),
        'workspaceId': unit,
        'title': title,
        'status': 'open',
        'priority': 'none',
        'timezone': 'Europe/Istanbul',
        'isUrgent': false,
        'requiresAcknowledgement': false,
        'calendarMirrorEnabled': false,
        'sortOrder': 0,
        'createdBy': createdBy,
        'revision': revision,
        'createdAt': '2026-09-01T10:00:00.000Z',
        'updatedAt': '2026-09-01T10:00:00.000Z',
        'tagIds': const <String>[],
        'checklist': const <Map<String, dynamic>>[],
      },
    });
    for (final person in on) {
      final assignmentId = _id('A$id${person.substring(0, 3)}');
      rows[unit]!.add({
        'revision': revision,
        'entityType': 'ee_task_assignment',
        'entityId': assignmentId,
        'operation': 'update',
        'data': {
          'id': assignmentId,
          'workspaceId': unit,
          'taskId': _id(id),
          'userId': person,
          'assignedBy': null,
          'assignedAt': '2026-09-01T10:00:00.000Z',
          'revision': revision,
          'updatedAt': '2026-09-01T10:00:00.000Z',
        },
      });
    }
  }

  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final path = options.uri.path;
    if (path == '/api/v1/me') {
      return jsonBody(200, {
        'user': {
          'id': _me,
          'email': 'ayla@example.com',
          'displayName': 'Ayla',
          'timezone': 'Europe/Istanbul',
          'locale': 'tr-TR',
          'createdAt': '2026-07-14T00:00:00.000Z',
          'deletionScheduledAt': null,
        },
        'workspaces': [
          {
            'id': _own,
            'name': 'Ayla',
            'slug': 'ayla',
            'colorRgb': '#2563EB',
            'icon': null,
            'role': 'owner',
            'owned': true,
          },
          {
            'id': _unitA,
            'name': 'Bakım',
            'slug': 'bakim',
            'colorRgb': '#16A34A',
            'icon': null,
            'role': 'member',
            'owned': false,
          },
          {
            'id': _unitB,
            'name': 'Üretim',
            'slug': 'uretim',
            'colorRgb': '#7C3AED',
            'icon': null,
            'role': 'member',
            'owned': false,
          },
        ],
      });
    }
    if (path == '/api/v1/sync/pull') {
      final workspaceId = options.uri.queryParameters['workspaceId']!;
      final since = int.parse(options.uri.queryParameters['sinceRevision']!);
      pulled.add(workspaceId);
      return jsonBody(200, {
        'workspaceId': workspaceId,
        'fromRevision': since,
        'toRevision': math.max(since, revision),
        'hasMore': false,
        'changes': since < revision ? rows[workspaceId]! : const [],
      });
    }
    if (path == '/api/v1/sync/push') {
      final mutations = ((body?['mutations'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final results = <Map<String, dynamic>>[];
      for (final m in mutations) {
        pushed.add({...m, 'workspaceId': body!['workspaceId']});
        revision += 1;
        results.add({
          'clientMutationId': m['clientMutationId'],
          'status': 'applied',
          'revision': revision,
          'errorCode': null,
          'replayed': false,
          'discardedFields': const <String>[],
        });
      }
      return jsonBody(200, {
        'workspaceId': body?['workspaceId'],
        'toRevision': revision,
        'results': results,
      });
    }
    return jsonBody(404, {
      'statusCode': 404,
      'code': 'NOT_FOUND',
      'error': 'Not Found',
      'message': 'No fake route for $path',
    });
  }
}

Future<Widget> _app(_TeamApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

/// EE-296 — in an organisation's app there is no personal space: Home is the
/// person's own work list, not a shared view of a unit.
void main() {
  // Tall enough that every row of Home is built: a lazy list only builds what
  // is on screen, and "not built" must not read as "not on Home".
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  _TeamApi seeded() {
    final api = _TeamApi()
      ..task('MINE', _unitA, 'Pres bakımı', createdBy: _colleague, on: [_me])
      ..task(
        'THEIRS',
        _unitA,
        'Kolega işi',
        createdBy: _colleague,
        on: [_colleague],
      )
      ..task('MADE', _unitB, 'Vardiya notu', createdBy: _me)
      ..task('GIVEN', _unitB, 'Verdiğim iş', createdBy: _me, on: [_colleague])
      ..task('LOOSE', _unitB, 'Ortada kalan', createdBy: _colleague);
    return api;
  }

  testWidgets("a member's Home is their work, from every unit they are in", (
    tester,
  ) async {
    tall(tester);
    final api = seeded();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    // Every unit is synced — not only the one selected — and the account's
    // own workspace is left to the drafts courier.
    expect(api.pulled, containsAll([_unitA, _unitB]));

    // Assigned to me (unit A), and made by me with nobody on it (unit B).
    expect(find.text('Pres bakımı'), findsOneWidget);
    expect(find.text('Vardiya notu'), findsOneWidget);
    // A colleague's work sits in the same units and never on this Home — nor
    // does what I handed to somebody else, nor what nobody has taken.
    expect(find.text('Kolega işi'), findsNothing);
    expect(find.text('Verdiğim iş'), findsNothing);
    expect(find.text('Ortada kalan'), findsNothing);

    // Two units: each row names its own.
    expect(
      find.descendant(
        of: find.byKey(Key('task-unit-${_id('MINE')}')),
        matching: find.text('Bakım'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('task-unit-${_id('MADE')}')),
        matching: find.text('Üretim'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the switcher offers the units, never the account\'s own', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(await _app(seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('workspace-switcher')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace-option-$_unitA')), findsOneWidget);
    expect(find.byKey(const Key('workspace-option-$_unitB')), findsOneWidget);
    expect(find.byKey(const Key('workspace-option-$_own')), findsNothing);
  });

  testWidgets('a quick add lands in the unit on screen, on its author', (
    tester,
  ) async {
    tall(tester);
    final api = seeded();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('home-quick-add')), 'Yeni iş');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Bounded pumps: the bar's spinner animates until onAdd returns, so a
    // pumpAndSettle with the deadline prompt open would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Add without date'));
    await tester.pumpAndSettle();

    final create = api.pushed.singleWhere(
      (m) => m['entityType'] == 'task' && m['operation'] == 'create',
    );
    // The first of the organisation's units is the one on screen.
    expect(create['workspaceId'], _unitA);
    final assign = api.pushed.singleWhere(
      (m) => m['entityType'] == 'ee_task_assignment',
    );
    expect(assign['workspaceId'], _unitA);
    expect((assign['patch'] as Map)['taskId'], create['entityId']);
    expect((assign['patch'] as Map)['userId'], _me);
    // …and so it is on this person's Home at once.
    expect(find.text('Yeni iş'), findsOneWidget);
  });
}
