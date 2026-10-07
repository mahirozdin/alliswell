import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/data/performance_api.dart';
import 'package:alliswell/src/features/ee/performance_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/performance_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-268 — AW-E21 on the screen: the performance panel answers "how long do
/// repairs take, apart from access requests?" with two rows.
///
/// Pumped against the REAL client over a fake HTTP layer, so the server's
/// `processTypes` is what gets parsed — including the kind of work becoming
/// the row's key, which a provider-level fake would simply agree with.
Map<String, dynamic> _row(
  String? type, {
  required int resolved,
  required double mttr,
  double? compliance,
}) => {
  'processType': type,
  'opened': resolved,
  'answered': resolved,
  'resolved': resolved,
  'backlogDelta': 0,
  'mtta': {'minutes': 12.0, 'measured': resolved, 'total': resolved},
  'mttr': {'minutes': mttr, 'measured': resolved, 'total': resolved},
  'compliance': compliance,
};

class _Server implements HttpClientAdapter {
  List<Map<String, dynamic>> processTypes = [];
  final List<RequestOptions> asked = [];

  /// OPH-357: answer like the limiter of an older server — a 429 with no
  /// `code`, only a Retry-After header — until switched off.
  bool limited = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    if (limited) {
      return ResponseBody.fromString(
        jsonEncode({
          'statusCode': 429,
          'error': 'Too Many Requests',
          'message': 'Rate limit exceeded, retry in 42 seconds',
        }),
        429,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'retry-after': ['42'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'from': '2026-08-27',
        'to': '2026-09-25',
        'units': <Object>[],
        'agents': <Object>[],
        'closedIsNotPerformance':
            'Kapanan talep sayısı bir performans ölçüsü değildir.',
        'processTypes': processTypes,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    server = _Server();
  });

  Future<void> pump(WidgetTester tester, {bool entitled = true}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          eePerformanceApiProvider.overrideWithValue(EePerformanceApi(dio)),
          eeFeatureProvider.overrideWith((ref, name) => entitled),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EePerformanceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inRow(String key, String text) => find.descendant(
    of: find.byKey(Key('perf-row-$key')),
    matching: find.text(text),
  );

  testWidgets('AW-E21: "how long do repairs take, apart from access '
      'requests?" — two rows, each with its MTTR and its promise', (
    tester,
  ) async {
    server.processTypes = [
      _row('incident', resolved: 2, mttr: 330, compliance: 50),
      _row('request', resolved: 1, mttr: 420, compliance: 100),
    ];
    await pump(tester);

    expect(
      inRow('incident', 'ee.perfPanel.processType.incident'.tr()),
      findsOneWidget,
    );
    expect(inRow('incident', '5 sa 30 dk'), findsOneWidget);
    expect(inRow('incident', '%50,0'), findsOneWidget);
    expect(
      inRow('request', 'ee.perfPanel.processType.request'.tr()),
      findsOneWidget,
    );
    expect(inRow('request', '7 sa'), findsOneWidget);
    expect(inRow('request', '%100,0'), findsOneWidget);
    // Satisfaction is asked per unit and per person, never per kind of work:
    // a CSAT dash on these rows would read as "nobody answered".
    expect(inRow('incident', 'ee.perfPanel.csat'.tr()), findsNothing);
    // First on the panel: it is the question the panel is opened to answer.
    expect(
      tester.getTopLeft(find.text('ee.perfPanel.byProcessType'.tr())).dy,
      lessThan(tester.getTopLeft(find.text('ee.perfPanel.byUnit'.tr())).dy),
    );
  });

  testWidgets(
    'UI-AUDIT #88: figures are written in the reader\'s locale — "%40,3", "3 g 21 sa", never "5587.5 dk"',
    (tester) async {
      server.processTypes = [
        _row('incident', resolved: 3, mttr: 5587.5, compliance: 40.3),
      ];
      await pump(tester);
      expect(inRow('incident', '%40,3'), findsOneWidget);
      expect(inRow('incident', '3 g 21 sa'), findsOneWidget);
      expect(find.textContaining('5587'), findsNothing);
      expect(find.textContaining('40.3'), findsNothing);
    },
  );

  testWidgets('work counted with no kind is named, not dropped', (
    tester,
  ) async {
    server.processTypes = [
      _row('incident', resolved: 1, mttr: 60),
      _row('request', resolved: 0, mttr: 0),
      _row(null, resolved: 3, mttr: 90),
    ];
    await pump(tester);
    expect(inRow('none', 'ee.perfPanel.processTypeNone'.tr()), findsOneWidget);
  });

  testWidgets('UI-AUDIT #24: a refused read says so in Turkish, with the '
      'wait, and Retry asks again', (tester) async {
    server.limited = true;
    await pump(tester);

    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('Unexpected server response'), findsNothing);
    expect(
      find.text('error.RATE_LIMITED'.tr(args: {'seconds': '42'})),
      findsOneWidget,
    );
    expect(find.textContaining('42 sn'), findsOneWidget);

    server.limited = false;
    server.processTypes = [_row('incident', resolved: 3, mttr: 60)];
    final before = server.asked.length;
    await tester.tap(find.text('common.retry'.tr()));
    await tester.pumpAndSettle();
    expect(server.asked.length, before + 1);
    expect(find.byKey(const Key('perf-row-incident')), findsOneWidget);
  });

  testWidgets('without the entitlement nothing is asked', (tester) async {
    await pump(tester, entitled: false);
    expect(server.asked, isEmpty);
  });
}
