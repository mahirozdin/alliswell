import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
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
    expect(
      inRow('incident', 'ee.perfPanel.minutes'.tr(args: {'minutes': '330.0'})),
      findsOneWidget,
    );
    expect(
      inRow('incident', 'ee.perfPanel.percent'.tr(args: {'value': '50.0'})),
      findsOneWidget,
    );
    expect(
      inRow('request', 'ee.perfPanel.processType.request'.tr()),
      findsOneWidget,
    );
    expect(
      inRow('request', 'ee.perfPanel.minutes'.tr(args: {'minutes': '420.0'})),
      findsOneWidget,
    );
    expect(
      inRow('request', 'ee.perfPanel.percent'.tr(args: {'value': '100.0'})),
      findsOneWidget,
    );
    // Satisfaction is asked per unit and per person, never per kind of work:
    // a CSAT dash on these rows would read as "nobody answered".
    expect(inRow('incident', 'ee.perfPanel.csat'.tr()), findsNothing);
    // First on the panel: it is the question the panel is opened to answer.
    expect(
      tester.getTopLeft(find.text('ee.perfPanel.byProcessType'.tr())).dy,
      lessThan(tester.getTopLeft(find.text('ee.perfPanel.byUnit'.tr())).dy),
    );
  });

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

  testWidgets('without the entitlement nothing is asked', (tester) async {
    await pump(tester, entitled: false);
    expect(server.asked, isEmpty);
  });
}
