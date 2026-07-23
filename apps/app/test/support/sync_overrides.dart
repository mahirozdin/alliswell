import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/features/onboarding/tour.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_socket.dart';

import 'fake_notifications.dart';
import 'fake_widget_host.dart';

/// Overrides every widget test pumping the full app needs since local-first
/// (OPH-054): an in-memory replica instead of the platform-channel database,
/// no periodic pull timer (would outlive the test body), and a zero debounce
/// so a pumpAndSettle carries writes through push+pull deterministically.
/// Pass [socketFactory] to observe/drive the live socket (default: none).
List<Override> syncTestOverrides({
  SyncSocketFactory? socketFactory,
  bool tourAutoStart = false,
  bool alarmOverlayAutoShow = false,
  Future<List<PickedUpload>> Function()? filePicker,
  UploadTransport? uploadTransport,
}) => [
  databaseProvider.overrideWith((ref) {
    // closeStreamsSynchronously: drift otherwise keeps a Timer.run alive per
    // cancelled watch stream (its stream cache), which trips flutter_test's
    // pending-timer teardown check.
    final db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ref.onDispose(db.close);
    return db;
  }),
  syncPullIntervalProvider.overrideWithValue(null),
  syncDebounceProvider.overrideWithValue(Duration.zero),
  // No real sockets (and no reconnect timers) inside the fake-async zone.
  syncSocketFactoryProvider.overrideWithValue(socketFactory),
  // No platform channels: notifications go to an in-memory fake.
  notificationsGatewayProvider.overrideWith(
    (ref) => FakeNotificationsGateway(),
  ),
  // No platform channels: AlarmKit (OPH-141) reports unsupported, so the
  // scheduler keeps urgent alarms on the (fake) notification lane.
  alarmKitHostProvider.overrideWithValue(const UnsupportedAlarmKitHost()),
  // The first-run onboarding tour must never auto-start over a widget test
  // (OPH-111) — it would cover the UI the test is driving. Tests that assert
  // the tour opt back in with `tourAutoStart: true`.
  tourAutoStartProvider.overrideWithValue(tourAutoStart),
  // Same idiom for the foreground alarm ring (OPH-143): a due urgent alarm
  // must not cover the app under test. Ring tests opt in with
  // `alarmOverlayAutoShow: true`. Feedback is silenced so no haptic timer
  // outlives the test body.
  alarmOverlayAutoShowProvider.overrideWithValue(alarmOverlayAutoShow),
  alarmFeedbackProvider.overrideWithValue(const SilentAlarmFeedback()),
  // No platform channels: the home-screen widget bridge (OPH-130), watched by
  // HomeShell, pushes to an in-memory fake instead of home_widget.
  widgetHostProvider.overrideWithValue(FakeWidgetHost()),
  // No platform channels: the file picker (OPH-153) answers "picked nothing"
  // unless a test passes fake picks of its own via [filePicker].
  filePickerProvider.overrideWithValue(filePicker ?? () async => const []),
  // No network: the presigned PUT succeeds instantly with full progress
  // unless a test injects its own transport (failure/cancel scenarios).
  uploadTransportProvider.overrideWithValue(
    uploadTransport ?? _instantUploadTransport,
  ),
];

Future<void> _instantUploadTransport({
  required String url,
  required Map<String, String> headers,
  required PickedUpload source,
  void Function(int sent, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  onProgress?.call(source.sizeBytes, source.sizeBytes);
}
