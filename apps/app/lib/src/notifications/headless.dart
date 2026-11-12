import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import '../core/app_liveness.dart';
import '../core/kv/local_kv.dart';
import '../core/server_url.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/models.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/token_storage.dart';
import '../features/auth/data/secret_store.dart';
import '../features/auth/data/secure_secret_store.dart';
import '../features/auth/data/auth_interceptor.dart';
import '../features/devices/device_registry.dart';
import '../features/tasks/data/task_scope.dart';
import '../features/widgets/widget_bridge.dart';
import '../features/widgets/widget_host.dart';
import '../i18n/i18n.dart';
import '../sync/db/connection.dart';
import '../sync/db/database.dart';
import '../sync/local_data.dart';
import '../sync/sync_api.dart';
import '../sync/sync_engine.dart';
import 'alarm_sound.dart';
import 'device_gate.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'os_alarms.dart';
import 'planner.dart';
import 'reminder_profile.dart';
import 'reminder_store.dart';
import 'sound_store.dart';
import 'scheduler.dart';

/// One background turn: sync, then re-arm the OS alarms (OPH-321), then redraw
/// the home-screen widget from the replica (OPH-334).
///
/// ── WHY THERE IS NO PROVIDER CONTAINER HERE ───────────────────────────────
///
/// Building one was the obvious move and it is rejected on purpose. The graph
/// is UI-shaped: long-lived streams, a pull timer, an `AppLifecycleListener`
/// that binds to `WidgetsBinding`, a router — and `currentWorkspaceProvider`
/// makes a NETWORK call, so a container built at 3 a.m. offline would resolve
/// to "no workspace" and this turn would schedule nothing while believing it
/// had done its job. Three objects by hand say what they depend on; a
/// container hides it.
///
/// ── AND WHY THE ORDER IS THE ORDER ────────────────────────────────────────
///
/// Every step below was chosen because the obvious alternative is wrong here,
/// not because it reads nicely:
///
/// 1. [AwI18n.boot] is MANDATORY and first. A notification's text goes through
///    `.tr()`, and an unbooted catalogue renders keys — so the identity a
///    notification is scheduled under would differ from the one the live app
///    produces, and the same alarm would be scheduled twice under two ids.
/// 2. The workspaces come from `sync_states` — every row, one per workspace
///    the app keeps in sync (a member of an organisation syncs all of their
///    units) — never from `/me`: that is a network call, and offline it fails
///    into "sync nothing". WHOSE alarms and widget come from the scope the app
///    last built its lists from ([recallTaskScope]); a replica no build of
///    that kind has run on yet is read the way the build before it read it,
///    one workspace, whole.
/// 3. The base URL is read from [localKv] DIRECTLY. `PersistedChoice` answers
///    its fallback synchronously and hydrates after — in a process this short
///    that fallback IS the answer, and a self-hoster would be sent to the
///    hosted API with their own token.
/// 4. No session means exit, silently. A signed-out install has nothing to
///    sync and nothing to schedule.
/// 5. `syncNow()`, not `start()`: `start` installs a pull timer this process
///    will never live to fire.
/// 6. A refresh refused as revoked (OPH-447: the device was removed on
///    another device) ends the turn the way the foreground ends such a
///    session ([endRevokedSessionHeadless]) instead of re-arming alarms from
///    the rows of a session that no longer exists. Nobody else will: the next
///    launch restores no session, so its revocation cleanup never runs.
///
/// [secretStore] and [httpAdapter] are test seams; production reads the
/// platform store and talks to the network.
Future<void> runHeadlessRefresh({
  AwDatabase Function()? openDatabase,
  AppLiveness? liveness,
  NotificationsGateway Function()? openGateway,
  WidgetHost? widgetHost,
  @visibleForTesting SecretStore? secretStore,
  @visibleForTesting HttpClientAdapter? httpAdapter,
}) async {
  // The app is in front of the user and already doing this, continuously
  // (OPH-318). WAL makes the overlap survivable; not overlapping is cheaper.
  if (await (liveness ?? appLiveness).isForeground(DateTime.now())) return;

  await AwI18n.instance.boot();

  final db = openDatabase?.call() ?? AwDatabase(openAwConnection());
  try {
    final synced = [
      for (final state in await db.select(db.syncStates).get())
        state.workspaceId,
    ];
    if (synced.isEmpty) return;
    final remembered = await recallTaskScope(syncedWorkspaceIds: synced);
    TaskScope? scope = remembered?.scope ?? TaskScope.workspace(synced.first);

    try {
      final baseUrl =
          await localKv.get(kServerUrlPrefKey) ?? compiledApiBaseUrl;

      Dio client() {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        if (httpAdapter != null) dio.httpClientAdapter = httpAdapter;
        return dio;
      }

      String? revokedUserId;
      final repository = AuthRepository(
        api: AuthApi(client()),
        storage: TokenStorage(secretStore ?? defaultSecretStore()),
        // Only noted here: the cleanup runs below, once the sync round that
        // heard the refusal is over (a request is still waiting on it).
        onSessionRevoked: (userId) async => revokedUserId = userId,
      );
      // A Keychain that cannot be read is not an error here, it is an answer:
      // iOS stores the session under `kSecAttrAccessibleWhenUnlocked`, so a
      // wake on a locked phone reads nothing (ADR-0038 §8). Treating that as
      // "signed out" is what makes this turn a no-op instead of a crash loop.
      AuthSession? session;
      try {
        session = await repository.restore();
      } on Object {
        session = null;
      }
      if (session == null) return;
      if (remembered != null && remembered.userId != session.user.id) {
        // Left by an account that is no longer the one signed in. Its lists
        // are not this person's: nothing is scheduled or drawn from them, and
        // the app builds this person's own the next time it runs.
        scope = null;
        return;
      }

      final dio = client();
      dio.interceptors.add(
        AuthInterceptor(
          getAccessToken: () => repository.accessToken,
          refreshAccessToken: repository.refreshAccessToken,
        ),
      );

      final api = SyncApi(dio);
      for (final workspaceId in synced) {
        // The session is gone; the next workspace has nobody to sync as.
        if (revokedUserId != null) break;
        final engine = SyncEngine(db: db, api: api, workspaceId: workspaceId);
        try {
          await engine.syncNow();
        } on Object {
          // Offline, or the server said no. The replica still holds whatever
          // it held, and scheduling from stale rows beats scheduling nothing:
          // this turn exists because the app has not run, so those rows may
          // be the only ones the device will have until it does. One
          // workspace failing is not a reason to leave the next one stale.
        } finally {
          engine.dispose();
        }
      }

      final gateway = openGateway?.call() ?? LocalNotificationsGateway();
      final revoked = revokedUserId;
      if (revoked != null) {
        await endRevokedSessionHeadless(db, userId: revoked, gateway: gateway);
        return;
      }
      await rearmAlarmsFromReplica(db, scope: scope, gateway: gateway);
    } finally {
      // OPH-334: every path past this point — no session (a locked iPhone reads
      // no Keychain), offline, a server that said no — ends by redrawing the
      // widget from the replica. The rows may be stale; the DAY is not, and at
      // midnight the day is what moved. Never throws (see the function).
      if (scope != null) {
        await publishWidgetFromReplica(
          db,
          scope: scope,
          now: DateTime.now(),
          host: widgetHost,
        );
      }
    }
  } finally {
    // Always: a background isolate that leaves the file open is the second
    // writer the WAL work (OPH-318) was about.
    await db.close();
  }
}

/// What a background turn does when its refresh was refused as revoked
/// (OPH-447, headless-revocation-bypasses-cleanup): the same as the
/// foreground's revoked sign-out, minus what a wake isolate cannot reach.
///
/// Every alarm of this install leaves the OS, the one on screen included
/// ([dropEveryOsAlarm]; no AlarmKit here, the turn is Android's). The replica
/// is wiped only when nothing in it is unsent (OPH-355: a person who is not
/// asked loses nothing; the same person's next sign-in adopts it) and only
/// while it is still recorded as [userId]'s or nobody's. The push token is
/// not forgotten from here: the server dropped the device row with the
/// family, so nothing is sent to it.
Future<void> endRevokedSessionHeadless(
  AwDatabase db, {
  required String userId,
  required NotificationsGateway gateway,
  LocalKv? kv,
}) async {
  final store = kv ?? localKv;
  if (kv == null) await reloadSharedPreferences();
  final owner = await store.get(kReplicaOwnerKey);
  if (owner == null || owner == userId) {
    // The outbox is checked inside the wipe's transaction, not before it: the
    // app can resume and commit an edit on its own connection while this
    // turn is still awaiting, and a count read earlier would let the wipe
    // delete that edit unasked (headless-revocation-wipe-race).
    await LocalDataGuard(database: () => db, kv: store).wipeIfNothingUnsent();
  }
  await dropEveryOsAlarm(gateway: gateway);
}

/// The alarm half of a headless turn: read the replica, put it through this
/// device's gate, apply it once.
///
/// The gate is the foreground's (OPH-452, #48): the same `forThisDevice` over
/// the same stored answer, read through the same [RingsUrgentStore]. Off and
/// unknown schedule every urgent alarm as an ordinary notification; on and
/// legacy (an install from before the answer existed) ring as they always
/// did. A turn that read the gate any other way would put back, at 3 a.m.,
/// the urgent chain the app took off this device.
///
/// [NotificationScheduler.applyOnce] is a full pass, so the Android
/// active-notification reconcile (OPH-445) runs here too: an alarm answered on
/// another device stops ringing on this one after the wake and sync.
///
/// [refreshKv] runs before anything is read. The Android wake isolate lives as
/// long as the process, and the legacy SharedPreferences behind [localKv]
/// keeps the copy that isolate loaded first: without the reload a wake after
/// the foreground turned this device on (or off) planned from the old gate and
/// undid it. Defaults to [reloadSharedPreferences] when [kv] is the shared
/// [localKv]; null when [kv] has no cache to refresh.
Future<void> rearmAlarmsFromReplica(
  AwDatabase db, {
  required TaskScope scope,
  required NotificationsGateway gateway,
  LocalKv? kv,
  Future<void> Function()? refreshKv,
}) async {
  final store = kv ?? localKv;
  await (refreshKv ?? (kv == null ? reloadSharedPreferences : null))?.call();
  final here = await RingsUrgentStore(kv: store).read();
  final alarms = forThisDevice(
    await ReminderStore(db, () {}).readAlarmsIn(scope),
    here,
  );
  final scheduler = NotificationScheduler(
    gateway: gateway,
    // Nothing streams here; the set is read once and applied once.
    alarms: const Stream<List<AlarmInput>>.empty(),
    privacyMode: (await store.get('notification_privacy')) == 'true',
    // The person's chain and sounds, as the foreground plans them: the sound
    // name is part of each id, so a turn on the defaults re-planned every
    // urgent alarm under new ids and the factory chain, with the default
    // sound, until the app next ran.
    profile: ReminderProfile.parse(await store.get(kReminderProfileKey)),
    sounds: AlarmSoundResolver(
      store: soundStore,
      isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    ),
    alarmSound: AwSoundChoice.parse(
      await store.get(kAlarmSoundKey) ?? kAlarmSoundFallback,
    ),
    reminderSound: AwSoundChoice.parse(
      await store.get(kReminderSoundKey) ?? kReminderSoundFallback,
    ),
  );
  try {
    await scheduler.applyOnce(alarms);
  } finally {
    scheduler.dispose();
  }
}
