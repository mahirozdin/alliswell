import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/data/meetings_api.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/files/providers.dart'
    show PickedUpload, filePickerProvider, uploadTransportProvider;
import 'package:alliswell/src/features/ee/ui/meetings_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// AW-E26 / EE-271 — the meetings list, asserted where it could mislead.
///
/// A list of meetings answers one question per row: is it ready, and what did
/// it decide. So a meeting still waiting for its note must read as WAITING
/// (the detail's rule, EE-115) and must not show a decision count it does not
/// have yet; and a list that needs the server must say so with no signal
/// rather than draw an old answer — or ask a network the app already knows is
/// gone.
class _FakeMeetings extends Fake implements EeMeetingsApi {
  List<EeMeetingSummary>? rows = const [];
  int listed = 0;

  @override
  Future<List<EeMeetingSummary>?> list(String workspaceId) async {
    listed += 1;
    return rows;
  }

  final calls = <String>[];

  @override
  Future<EeMeetingUploadSlot> create({
    required String workspaceId,
    required String mime,
    required int sizeBytes,
    String? title,
  }) async {
    calls.add('create $workspaceId $mime $sizeBytes $title');
    return EeMeetingUploadSlot(
      meeting: _meeting('M9', title ?? '', EeMeetingStatus.awaitingUpload),
      url: 'https://store.example/put/M9',
      headers: const {'content-type': 'audio/mpeg'},
    );
  }

  @override
  Future<EeMeetingSummary> complete(String meetingId) async {
    calls.add('complete $meetingId');
    return _meeting(meetingId, 'kayit', EeMeetingStatus.queued);
  }
}

EeMeetingSummary _meeting(
  String id,
  String title,
  EeMeetingStatus status, {
  int decisions = 0,
  int ideas = 0,
}) => EeMeetingSummary(
  id: id,
  workspaceId: 'W1',
  status: status,
  attempts: 1,
  decisionCount: decisions,
  ideaCount: ideas,
  createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  title: title,
);

void main() {
  late _FakeMeetings api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeMeetings();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool entitled = true,
    bool offline = false,
    List<PickedUpload> picked = const [],
    List<String>? puts,
  }) async {
    final container = ProviderContainer(
      overrides: [
        eeMyUnitsScopeProvider.overrideWith((ref) async => null),
        workspacesProvider.overrideWith((ref) async => const []),
        filePickerProvider.overrideWithValue((source) async => picked),
        uploadTransportProvider.overrideWithValue(({
          required url,
          required headers,
          required source,
          onProgress,
          cancelToken,
        }) async {
          puts?.add('PUT $url ${source.name}');
        }),
        eeMeetingsApiProvider.overrideWithValue(api),
        eeFeatureProvider.overrideWith((ref, name) => entitled),
        syncEngineProvider.overrideWithValue(null),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: 'W1',
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (offline) {
      container.read(serverReachabilityProvider.notifier).unreachable();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeMeetingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder key(String k) => find.byKey(Key(k));

  testWidgets('AW-E26: a ready meeting says what it decided; a waiting one '
      'reads as waiting and claims no decisions', (tester) async {
    api.rows = [
      _meeting(
        'M1',
        'Vardiya devri',
        EeMeetingStatus.ready,
        decisions: 3,
        ideas: 2,
      ),
      _meeting('M2', 'Kalite gözden geçirme', EeMeetingStatus.transcribed),
    ];
    await pump(tester);

    expect(key('meeting-M1'), findsOneWidget);
    expect(
      find.text(
        'ee.meetings.counts'.tr(args: {'decisions': '3', 'ideas': '2'}),
      ),
      findsOneWidget,
    );
    // `transcribed` is WAITING: the word says the note is still being
    // written, and there is no count to show until it is.
    expect(
      find.descendant(
        of: key('meeting-M2'),
        matching: find.textContaining('ee.meeting.status.transcribed'.tr()),
      ),
      findsOneWidget,
    );
    expect(key('meeting-counts-M2'), findsNothing);
  });

  testWidgets('AW-E26: with no signal the list says it needs a connection — '
      'and asks nothing', (tester) async {
    api.rows = [_meeting('M1', 'Vardiya devri', EeMeetingStatus.ready)];
    await pump(tester, offline: true);
    expect(key('meetings-offline'), findsOneWidget);
    expect(key('meeting-M1'), findsNothing);
    expect(api.listed, 0);
  });

  testWidgets('without the entitlement the list says meetings are not here', (
    tester,
  ) async {
    await pump(tester, entitled: false);
    expect(key('meetings-unavailable'), findsOneWidget);
    expect(api.listed, 0);
  });

  testWidgets('a unit with no meetings says so', (tester) async {
    api.rows = const [];
    await pump(tester);
    expect(key('meetings-empty'), findsOneWidget);
  });

  // OPH-359 — UI-AUDIT #54.
  testWidgets('UI-AUDIT #54: a failed row says why, from its code', (
    tester,
  ) async {
    api.rows = [
      EeMeetingSummary(
        id: 'M2',
        workspaceId: 'W1',
        status: EeMeetingStatus.failed,
        attempts: 1,
        decisionCount: 0,
        ideaCount: 0,
        createdAt: DateTime.now(),
        title: 'Sessiz kayıt',
        failureCode: 'MEETING_NO_TRANSCRIBER',
        failureMessage: 'This team has no transcription provider configured.',
      ),
    ];
    await pump(tester);
    expect(
      tester.widget<Text>(key('meeting-reason-M2')).data,
      'ee.meeting.failure.MEETING_NO_TRANSCRIBER'.tr(),
    );
    expect(find.textContaining('transcription provider'), findsNothing);
  });

  testWidgets('UI-AUDIT #54: "upload a recording" opens the meeting, puts the '
      'bytes in its slot and says it is there', (tester) async {
    final puts = <String>[];
    await pump(
      tester,
      picked: [
        PickedUpload.fromBytes(
          name: 'vardiya.mp3',
          bytes: Uint8List.fromList(List.filled(32, 1)),
        ),
      ],
      puts: puts,
    );
    final listedBefore = api.listed;
    await tester.tap(key('meetings-upload'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create W1 audio/mpeg 32 vardiya', 'complete M9']);
    expect(puts, ['PUT https://store.example/put/M9 vardiya.mp3']);
    // The list is asked again, so the new meeting appears.
    expect(api.listed, greaterThan(listedBefore));
    expect(find.text('ee.meetings.uploaded'.tr()), findsOneWidget);
  });

  testWidgets('no upload button where the instance has no meetings', (
    tester,
  ) async {
    await pump(tester, entitled: false);
    expect(key('meetings-upload'), findsNothing);
  });
}
