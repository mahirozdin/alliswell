import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/absences_providers.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/absences_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/absences_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-236 — AW-E18 on the screen: somebody writes "I am away", and the next
/// thing they see is who has the pager instead.
///
/// Pumped against the REAL client over a fake HTTP layer, so the server's
/// JSON is what gets parsed and what gets SENT is asserted — a fake at the
/// provider level would agree with whatever the model expected.
const _me = '01USERMEAAAAAAAAAAAAAAAAAA';
const _burak = '01USERBURAKAAAAAAAAAAAAAAA';
const _unit = '01UNITAAAAAAAAAAAAAAAAAAAA';

class _Server implements HttpClientAdapter {
  Map<String, dynamic> list = {
    'absences': [],
    'truncated': false,
    'canManage': false,
    'today': '2026-09-25',
  };
  List<Map<String, dynamic>> onCall = [];
  ResponseBody Function(RequestOptions options)? create;
  final List<RequestOptions> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    if (options.path == '/api/v1/ee/team/oncall/mine') {
      return _json(200, {'units': onCall});
    }
    if (options.method == 'POST') return create!(options);
    if (options.method == 'DELETE') return ResponseBody.fromString('', 204);
    return _json(200, list);
  }

  @override
  void close({bool force = false}) {}
}

class _Offline extends ServerReachability {
  @override
  bool? build() => false;
}

ResponseBody _json(int status, Object data) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _absence(
  String id,
  String userId,
  String name,
  String from,
  String to,
) => {
  'id': id,
  'userId': userId,
  'userName': name,
  'startDate': from,
  'endDate': to,
  'createdBy': userId,
  'createdAt': '2026-09-20T08:00:00.000Z',
};

void main() {
  late _Server server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    server = _Server();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Override> extra = const [],
    bool entitled = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          eeAbsencesApiProvider.overrideWithValue(EeAbsencesApi(dio)),
          eeFeatureProvider.overrideWith((ref, name) => entitled),
          currentUserIdProvider.overrideWithValue(_me),
          workspaceRosterProvider.overrideWith(
            (ref) => Stream.value(const [
              MemberProfile(
                id: 'MP1',
                workspaceId: 'W1',
                userId: _me,
                displayName: 'Ayşe',
                colorRgb: '#2563EB',
                revision: 1,
              ),
              MemberProfile(
                id: 'MP2',
                workspaceId: 'W1',
                userId: _burak,
                displayName: 'Burak',
                colorRgb: '#16A34A',
                revision: 1,
              ),
            ]),
          ),
          ...extra,
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeAbsencesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AW-E18: she records her week away, and the screen says who '
      'covers her turn', (tester) async {
    server.create = (options) {
      final body = options.data as Map<String, dynamic>;
      server.list = {
        ...server.list,
        'absences': [
          _absence(
            'A1',
            _me,
            'Ayşe',
            body['startDate'] as String,
            body['endDate'] as String,
          ),
        ],
      };
      server.onCall = [
        {
          'unitId': _unit,
          'unitName': 'Bakım',
          'userId': _burak,
          'userName': 'Burak',
          'coveringFor': _me,
          'coveringForName': 'Ayşe',
          'since': '2026-09-24T21:00:00.000Z',
          'until': '2026-10-01T06:00:00.000Z',
        },
      ];
      return _json(
        201,
        _absence('A1', _me, 'Ayşe', '2026-09-25', '2026-09-25'),
      );
    };
    await pump(tester);
    expect(find.byKey(const Key('absences-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('absences-add')));
    await tester.pumpAndSettle();
    // A member records their own: no person to choose — and the v1 limits
    // are said where the absence is written.
    expect(find.byKey(const Key('absence-person')), findsNothing);
    expect(find.byKey(const Key('absences-limits')), findsOneWidget);
    await tester.tap(find.byKey(const Key('absence-save')));
    await tester.pumpAndSettle();

    final sent = server.asked.firstWhere((o) => o.method == 'POST');
    expect(sent.data, {'startDate': '2026-09-25', 'endDate': '2026-09-25'});
    // Back on the list: her absence, and the rota's answer — who covers.
    expect(find.byKey(const Key('absence-A1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('absence-A1')),
        matching: find.text('ee.absences.you'.tr()),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('oncall-$_unit')), findsOneWidget);
    expect(find.textContaining('Burak'), findsOneWidget);
    expect(find.textContaining('sizin yerinize'), findsOneWidget);
  });

  testWidgets('a member may remove their own and not a colleague’s; removing '
      'asks first', (tester) async {
    server.list = {
      ...server.list,
      'absences': [
        _absence('A1', _me, 'Ayşe', '2026-10-05', '2026-10-09'),
        _absence('A2', _burak, 'Burak', '2026-10-12', '2026-10-12'),
      ],
    };
    await pump(tester);
    expect(find.byKey(const Key('absence-remove-A1')), findsOneWidget);
    expect(find.byKey(const Key('absence-remove-A2')), findsNothing);

    // Asking first means "cancel" removes nothing.
    await tester.tap(find.byKey(const Key('absence-remove-A1')));
    await tester.pumpAndSettle();
    expect(find.text('ee.absences.removeTitle'.tr()), findsOneWidget);
    await tester.tap(find.text('common.cancel'.tr()));
    await tester.pumpAndSettle();
    expect(server.asked.where((o) => o.method == 'DELETE'), isEmpty);

    await tester.tap(find.byKey(const Key('absence-remove-A1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('absence-remove-confirm')));
    await tester.pumpAndSettle();
    final deleted = server.asked.where((o) => o.method == 'DELETE').toList();
    expect(deleted.single.path, '/api/v1/ee/team/absences/A1');
  });

  testWidgets('somebody who records for others picks the person, and may '
      'remove anyone’s', (tester) async {
    server.list = {
      ...server.list,
      'canManage': true,
      'absences': [_absence('A2', _burak, 'Burak', '2026-10-12', '2026-10-12')],
    };
    server.create = (_) =>
        _json(201, _absence('A3', _burak, 'Burak', '2026-09-25', '2026-09-25'));
    await pump(tester);
    expect(find.byKey(const Key('absence-remove-A2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('absences-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('absence-person')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burak').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('absence-save')));
    await tester.pumpAndSettle();
    final sent = server.asked.firstWhere((o) => o.method == 'POST');
    expect((sent.data as Map)['userId'], _burak);
  });

  testWidgets('an overlap is said in words, and the sheet stays open', (
    tester,
  ) async {
    server.create = (_) => _json(409, {
      'statusCode': 409,
      'code': 'ABSENCE_OVERLAP',
      'error': 'Conflict',
      'message': 'This person already has an absence on some of these days',
    });
    await pump(tester);
    await tester.tap(find.byKey(const Key('absences-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('absence-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('absence-error')), findsOneWidget);
    expect(find.text('error.ABSENCE_OVERLAP'.tr()), findsOneWidget);
    expect(find.byKey(const Key('absence-save')), findsOneWidget);
  });

  testWidgets('everybody on the rota away: the card says so, not a name', (
    tester,
  ) async {
    server.onCall = [
      {
        'unitId': _unit,
        'unitName': 'Bakım',
        'userId': null,
        'userName': null,
        'coveringFor': _burak,
        'coveringForName': 'Burak',
        'since': null,
        'until': null,
      },
    ];
    await pump(tester);
    expect(find.text('ee.absences.onCallNobody'.tr()), findsOneWidget);
  });

  testWidgets('a cut list says it was cut', (tester) async {
    server.list = {
      ...server.list,
      'truncated': true,
      'absences': [_absence('A2', _burak, 'Burak', '2026-10-12', '2026-10-12')],
    };
    await pump(tester);
    expect(find.byKey(const Key('absences-truncated')), findsOneWidget);
  });

  testWidgets('when the app already knows it is offline, it names the '
      'connection and does not ask', (tester) async {
    await pump(
      tester,
      extra: [serverReachabilityProvider.overrideWith(_Offline.new)],
    );
    expect(find.byKey(const Key('absences-offline')), findsOneWidget);
    expect(server.asked, isEmpty);
  });

  testWidgets('without the entitlement nothing is asked', (tester) async {
    await pump(tester, entitled: false);
    expect(find.byKey(const Key('absences-empty')), findsOneWidget);
    expect(server.asked, isEmpty);
  });
}
