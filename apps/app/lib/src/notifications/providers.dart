import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/persisted_prefs.dart';
import '../features/devices/data/device_api.dart';
import '../features/devices/providers.dart';
import '../features/tasks/providers.dart';
import '../i18n/i18n.dart';
import '../router.dart';
import '../sync/db/database.dart';
import '../sync/providers.dart';
import 'actions.dart';
import 'web/alert_cache.dart';
import 'web/gateway_web.dart';
import 'web/push_host.dart';
import 'alarm_log.dart';
import 'alarm_sound.dart';
import 'alarmkit.dart';
import 'alarmkit_identity.dart';
import 'device_gate.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'reminder_profile.dart';
import 'reminder_store.dart';
import 'sound_store.dart';
import 'planner.dart' show AlarmInput;
import 'platform_matrix.dart';
import 'web_alert_mode.dart';
import 'scheduler.dart';

/// The OS adapter. Widget tests override this with a fake — the default
/// touches platform channels.
/// The gateway this platform can actually use.
///
/// Until OPH-313 this was `LocalNotificationsGateway()` with no platform guard
/// at all, including on the web — where `flutter_local_notifications` has no
/// implementation, so every call threw and the scheduler wrote a `degraded`
/// row. The browser gets a real gateway now; what it cannot do (schedule
/// locally) it says rather than swallows.
final notificationsGatewayProvider = Provider<NotificationsGateway>((ref) {
  // OPH-317: the choice has a name, so the documentation gate and a test can
  // ask the same question this line answers.
  if (gatewayKindFor(isWeb: kIsWeb) == NotificationGatewayKind.local) {
    return LocalNotificationsGateway();
  }

  late final WebNotificationsGateway gateway;
  gateway = WebNotificationsGateway(
    host: createWebPushHost(),
    readVapidKey: () => ref.read(pushPublicKeyProvider.future),
    serverHasPush: () => ref.read(pushServerConfiguredProvider.future),
    onSubscriptionChanged: () => unawaited(_publishSubscription(ref, gateway)),
    cache: createAlertCache(),
    // Read per notification rather than captured: the gateway outlives the
    // setting, and a tab that re-subscribed on every change would ask the
    // browser for a new endpoint each time somebody toggled a radio button.
    alertMode: () => ref.read(webAlertModeProvider),
    // The pair privacy mode already produces (`planner.dart:116-121`), so a
    // cache miss and a private device read identically rather than inventing a
    // third voice for the same moment.
    fallback: AlertText(title: 'AllisWell', body: 'notif.privateBody'.tr()),
  );
  // A tab that was already subscribed in an earlier session has one now, and
  // the registry needs to carry it on the first heartbeat rather than the one
  // after somebody happens to press the button again.
  unawaited(_publishSubscription(ref, gateway));
  // Turning delivery off has to reach the browser, not just the preference:
  // the subscription IS the thing the server sends to. One listener, so the
  // settings screen stays a screen.
  ref.listen<WebAlertMode>(
    webAlertModeProvider,
    (previous, next) => unawaited(gateway.applyAlertMode(next)),
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// Hands the browser's subscription to the device registry, then asks it to
/// send. One direction only: notifications knows about devices, not the
/// reverse.
Future<void> _publishSubscription(
  Ref ref,
  WebNotificationsGateway gateway,
) async {
  final subscription = await gateway.subscription();
  ref
      .read(devicePushCredentialsProvider.notifier)
      .set(
        subscription == null
            ? null
            : DevicePushCredentials.webPush(
                endpoint: subscription.endpoint,
                p256dh: subscription.p256dh,
                auth: subscription.auth,
              ),
      );
  await ref.read(deviceRegistryProvider).sync(signedIn: true);
}

/// iOS 26+ AlarmKit bridge (OPH-141, the URGENT lane that rings through the
/// mute switch). Tests override with a fake; the default talks to
/// `MethodChannel('alliswell/alarmkit')` and reports unsupported everywhere
/// else, so the scheduler keeps urgent alarms on notifications.
final alarmKitHostProvider = Provider<AlarmKitHost>(
  (_) => MethodChannelAlarmKitHost(),
);

/// What the scheduler last knew the OS holds on the AlarmKit lane (#46, iOS
/// 26+): its last `scheduledAlarms()` read, kept current by every schedule,
/// cancel and stop it made since. The ring overlay asks it whether an
/// occurrence already rings as a system alert (then the app stays quiet) and
/// which alarm an in-app action has to stop. Empty wherever AlarmKit is not
/// in use — Android, web, desktop, iOS < 26, permission off — so those keep
/// today's in-app sound.
class AlarmKitView extends Notifier<List<AlarmKitScheduled>> {
  AlarmKitView([this._initial = const []]);

  final List<AlarmKitScheduled> _initial;

  @override
  List<AlarmKitScheduled> build() => _initial;

  void replace(List<AlarmKitScheduled> rows) => state = List.unmodifiable(rows);

  /// An in-app action stopped [id]: it no longer covers anything.
  void remove(int id) {
    if (state.any((r) => r.id == id)) {
      state = List.unmodifiable(state.where((r) => r.id != id));
    }
  }
}

final alarmKitViewProvider =
    NotifierProvider<AlarmKitView, List<AlarmKitScheduled>>(AlarmKitView.new);

/// The scheduler's AlarmKit host, watched: every answer that tells what the
/// OS holds is folded into one list and handed to [onView] — the
/// [alarmKitViewProvider] feed. Everything else passes straight through.
class AlarmKitViewHost implements AlarmKitHost {
  AlarmKitViewHost(this._inner, {required this.onView});

  final AlarmKitHost _inner;
  final void Function(List<AlarmKitScheduled> rows) onView;
  final Map<int, AlarmKitScheduled> _rows = {};

  void _emit() => onView(List.unmodifiable(_rows.values));

  /// No lane, no view: an alarm the OS will not ring covers nothing.
  bool _lane(bool open) {
    if (!open && _rows.isNotEmpty) {
      _rows.clear();
      _emit();
    }
    return open;
  }

  @override
  Future<bool> isSupported() async => _lane(await _inner.isSupported());

  @override
  Future<bool> requestAuthorization() async =>
      _lane(await _inner.requestAuthorization());

  @override
  Future<bool> isAuthorized() async => _lane(await _inner.isAuthorized());

  @override
  Future<List<AlarmKitScheduled>> scheduledAlarms() async {
    final rows = await _inner.scheduledAlarms();
    _rows
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.id, r)));
    _emit();
    return rows;
  }

  @override
  Future<Set<int>> scheduledIds() => _inner.scheduledIds();

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async {
    final result = await _inner.schedule(alarm);
    if (result.ok) {
      _rows[alarm.id] = AlarmKitScheduled(
        id: alarm.id,
        fp: alarm.fp,
        members: alarm.members,
        fireAtMs: alarmKitFireAtMs(alarm.fireAt),
      );
      _emit();
    }
    return result;
  }

  @override
  Future<void> cancel(int id) async {
    await _inner.cancel(id);
    if (_rows.remove(id) != null) _emit();
  }

  @override
  Future<AlarmKitStopResult> stop(int id) async {
    final result = await _inner.stop(id);
    if (result.error == null && _rows.remove(id) != null) _emit();
    return result;
  }

  @override
  Future<List<AlarmKitActionEvent>> pullPendingActions() =>
      _inner.pullPendingActions();

  @override
  Future<void> ackActions(List<String> eventIds) => _inner.ackActions(eventIds);

  @override
  Future<void> clearFallbacks(List<String> eventIds) =>
      _inner.clearFallbacks(eventIds);

  @override
  Future<List<AlarmKitFailure>> pullFailures() => _inner.pullFailures();

  @override
  Stream<void> get actionsPending => _inner.actionsPending;
}

/// The user's re-alert chain (OPH-179, DESIGN §18). Device-local, like every
/// other delivery preference: each device schedules its own notifications, so
/// each device owns how insistent they are.
final reminderProfileRawProvider = NotifierProvider<PersistedChoice, String>(
  // Empty parses to the factory chain, so an upgrade changes nothing.
  () => PersistedChoice(kReminderProfileKey, fallback: ''),
);

/// The parsed profile — junk resolves to [ReminderProfile.factory].
final reminderProfileProvider = Provider<ReminderProfile>(
  (ref) => ReminderProfile.parse(ref.watch(reminderProfileRawProvider)),
);

/// The order the snooze presets appear in on the alarm screen (N4 — the one
/// list where dragging is meaningful).
final snoozePresetOrderRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(
    'alliswell_snooze_presets',
    fallback: '5_min,30_min,1_hour,tomorrow_morning',
  ),
);

final snoozePresetOrderProvider = Provider<List<String>>(
  (ref) => parseSnoozePresetOrder(ref.watch(snoozePresetOrderRawProvider)),
);

/// Which sound each lane plays (OPH-181). Device-local: the sound file lives on
/// THIS device, and the library it can be chosen from is the workspace's.
final alarmSoundRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(kAlarmSoundKey, fallback: kAlarmSoundFallback),
);

/// Ordinary reminders keep the OS sound until the user says otherwise.
final reminderSoundRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(kReminderSoundKey, fallback: kReminderSoundFallback),
);

/// How loud this BROWSER is (OPH-316). Device-local like every other delivery
/// preference, and the one the office asked for: the window without the sound.
/// Meaningless off the web — nothing reads it there.
///
/// Empty until the person picks a value (OPH-393): it parses to silent, the
/// default, but only a stored "silent" is a choice anyone made.
final webAlertModeRawProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_web_alert_mode', fallback: ''),
);

final webAlertModeProvider = Provider<WebAlertMode>(
  (ref) => WebAlertMode.parse(ref.watch(webAlertModeRawProvider)),
);

/// Whether the ring screen opens silent (OPH-316): this browser is set to
/// Silent — the web default (ADR-0039) — so the screen starts no sound and
/// says why rather than look like an alarm that failed. A provider rather than
/// a `kIsWeb` read inside the screen, because `kIsWeb` is a const `false` in a
/// VM test and the behaviour would then be untestable off the browser.
final alarmOpensSilentProvider = Provider<bool>(
  (ref) => kIsWeb && ref.watch(webAlertModeProvider) == WebAlertMode.silent,
);

/// Whether the person actually PICKED Silent (OPH-393, E-20). A fresh
/// browser is silent by default and nobody chose anything, so "you set this
/// browser to Silent" would be a false claim there. The stored value is empty
/// until the setting is touched — it still parses to silent.
final alarmSilenceChosenProvider = Provider<bool>(
  (ref) => ref.watch(webAlertModeRawProvider) == WebAlertMode.silent.id,
);

/// How many permission prompts are open right now (OPH-393, U-05).
///
/// The scheduler asks for notification (and AlarmKit) permission on start,
/// and Home probed at the same moment: the strip said "notifications are off"
/// behind the OS prompt that was asking to turn them on (ios/05), and stayed
/// there after the person allowed it, because nothing probed again. A count,
/// not a flag: a scheduler rebuilt mid-prompt asks once more before the first
/// ask ends.
class AlarmPermissionAsk extends Notifier<int> {
  @override
  int build() => 0;

  void begin() => state = state + 1;

  void end() => state = state > 0 ? state - 1 : 0;
}

final alarmPermissionAskProvider = NotifierProvider<AlarmPermissionAsk, int>(
  AlarmPermissionAsk.new,
);

/// Whether the browser will make a sound whatever the setting says (Firefox).
/// Asked through the gateway rather than by building a second host: the web
/// host installs a `serviceWorker.onmessage` handler, and two of those would
/// deliver every notification click twice.
final webIgnoresSilenceProvider = Provider<bool>((ref) {
  final gateway = ref.watch(notificationsGatewayProvider);
  return gateway is WebNotificationsGateway && gateway.ignoresSilence;
});

final alarmSoundChoiceProvider = Provider<AwSoundChoice>(
  (ref) => AwSoundChoice.parse(ref.watch(alarmSoundRawProvider)),
);

final reminderSoundChoiceProvider = Provider<AwSoundChoice>(
  (ref) => AwSoundChoice.parse(ref.watch(reminderSoundRawProvider)),
);

/// Resolves a choice into what this platform's notification lane can play.
final alarmSoundResolverProvider = Provider<AlarmSoundResolver>(
  (ref) => AlarmSoundResolver(
    store: soundStore,
    isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  ),
);

/// OPH-064: lock-screen privacy — generic notification content instead of
/// task titles. Persisted per device.
final notificationPrivacyProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('notification_privacy', fallback: false),
);

/// The device's alarm record (OPH-176, DESIGN §11 A6). Local only — it lives in
/// the replica database but is neither synced nor pushed.
final alarmLogProvider = Provider<AlarmLog>(
  (ref) => AlarmLog(ref.watch(databaseProvider)),
);

/// The log's newest rows, for the diagnostic screen.
final alarmLogRowsProvider = StreamProvider<List<AlarmEvent>>(
  (ref) => ref.watch(alarmLogProvider).watchRecent(),
);

final reminderStoreProvider = Provider<ReminderStore>(
  (ref) => ReminderStore(ref.watch(databaseProvider), () => pokeSync(ref)),
);

/// A one-shot probe of what alarm delivery the OS currently allows (OPH-139
/// [AlarmSupport]) — feeds the honest degradation banner (OPH-143). Invalidate
/// to re-probe (e.g. after the user returns from the permission flow).
final alarmSupportProvider = FutureProvider.autoDispose<AlarmSupport>((
  ref,
) async {
  final gateway = ref.watch(notificationsGatewayProvider);
  // Probe again the moment a permission prompt closes (OPH-393): what the
  // person just answered is the thing this reports.
  ref.watch(alarmPermissionAskProvider.select((open) => open > 0));
  try {
    await gateway.initialize();
    final support = await gateway.alarmSupport();
    // Never fail silently (NOTIFICATIONS §1): a device that cannot ring properly
    // says so on Home and in Settings — and now leaves a record too (OPH-176),
    // so "it didn't go off" can be checked against what the OS allowed.
    if (!support.notificationsEnabled || support.exactAlarmsEnabled == false) {
      // Fire-and-forget behind its OWN guard: a diagnostic must never change
      // what the probe reports. (It did once, in the making — an unavailable
      // database made the whole probe fail, so a device with alarms OFF looked
      // healthy. That is the exact lie A6 exists to prevent.)
      try {
        unawaited(
          ref
              .read(alarmLogProvider)
              .record(
                event: AlarmLogEvent.degraded,
                lane: AlarmLogLane.notification,
                detail:
                    'notifications=${support.notificationsEnabled} '
                    'exactAlarms=${support.exactAlarmsEnabled} '
                    'critical=${support.criticalAlertsEnabled}',
              ),
        );
      } on Object {
        // No log available (no database on this surface) — the probe stands.
      }
    }
    return support;
  } catch (_) {
    // Web / no platform channel: assume permissive so we never nag falsely.
    return const AlarmSupport(
      notificationsEnabled: true,
      criticalAlertsEnabled: false,
    );
  }
});

/// The gate's answer as the alarm paths use it: the stored state once read
/// (kept through a re-read), [RingsUrgentHere.unknown] if it cannot be read —
/// never ring on a guess — and null while the first read is in flight.
RingsUrgentHere? ringsUrgentHereNow(AsyncValue<RingsUrgentHere> stored) {
  if (stored.hasValue) return stored.value;
  if (stored.hasError) return RingsUrgentHere.unknown;
  return null;
}

/// [alarms] through the device gate (OPH-446) as [here] changes: each new
/// list or new answer emits `forThisDevice(latest list, latest answer)`.
/// Nothing is emitted before both are known — a plan made on a guess would
/// cancel and re-schedule the urgent chain on every launch.
Stream<List<AlarmInput>> gateAlarms(
  Stream<List<AlarmInput>> alarms,
  Stream<RingsUrgentHere> here,
) {
  late final StreamController<List<AlarmInput>> out;
  StreamSubscription<List<AlarmInput>>? alarmsSub;
  StreamSubscription<RingsUrgentHere>? hereSub;
  List<AlarmInput>? latest;
  RingsUrgentHere? gate;
  void emit() {
    final list = latest;
    final current = gate;
    if (list == null || current == null || out.isClosed) return;
    out.add(forThisDevice(list, current));
  }

  out = StreamController<List<AlarmInput>>(
    onListen: () {
      alarmsSub = alarms.listen((next) {
        latest = next;
        emit();
      }, onError: out.addError);
      hereSub = here.listen((next) {
        if (next == gate) return;
        gate = next;
        emit();
      });
    },
    onPause: () {
      alarmsSub?.pause();
      hereSub?.pause();
    },
    onResume: () {
      alarmsSub?.resume();
      hereSub?.resume();
    },
    onCancel: () async {
      await hereSub?.cancel();
      await alarmsSub?.cancel();
    },
  );
  return out.stream;
}

/// One scheduler per signed-in person: keeps the OS schedule equal to the
/// replica (OPH-061) and routes notification taps/actions into the stores
/// (OPH-062/063). Rebuilt when the privacy setting flips (OPH-064) so
/// content re-renders under the new policy.
///
/// autoDispose (OPH-452): it exists while HomeShell — a session — watches it,
/// so a signed-out app keeps no scheduler and no listener on the device gate.
final notificationSchedulerProvider = Provider.autoDispose<NotificationScheduler?>((
  ref,
) {
  // The person's own work — the same scope Home shows. In an organisation's
  // workspaces that is not "every task of the selected unit": a colleague's
  // reminder rang on every member's phone that happened to have that unit open.
  // `select`: a reload of the workspace list passes through loading, and a
  // scheduler rebuilt for it would re-plan the whole OS schedule for nothing.
  final scope = ref.watch(taskScopeProvider.select((s) => s.value));
  if (scope == null) return null;
  // Whether urgent alarms ring on THIS device (#48, OPH-452). Listened, not
  // watched: a new answer flows into the alarm stream below and re-plans at
  // once (urgent moves to or from AlarmKit and the chain), without tearing the
  // scheduler down and asking for permission again.
  final gate = StreamController<RingsUrgentHere>();
  ref.onDispose(gate.close);
  ref.listen<RingsUrgentHere?>(
    ringsUrgentHereProvider.select(ringsUrgentHereNow),
    (_, here) {
      if (here != null && !gate.isClosed) gate.add(here);
    },
    fireImmediately: true,
  );
  final gateway = ref.watch(notificationsGatewayProvider);
  final alarmKit = ref.watch(alarmKitHostProvider);
  final db = ref.watch(databaseProvider);

  // Taps/actions from EITHER lane route through the one handler — an AlarmKit
  // "Onayla"/"Ertele" is the same acknowledge/snooze as a notification button.
  // A pulled AlarmKit action carries an eventId and is applied exactly once
  // (OPH-427, NOTIFICATIONS §2b.3).
  Future<bool> onEvent(NotificationEvent event) => handleNotificationEvent(
    event,
    tasks: ref.read(taskStoreProvider),
    reminders: ref.read(reminderStoreProvider),
    navigate: (location) => ref.read(routerProvider).push(location),
    log: ref.read(alarmLogProvider),
    db: db,
  );
  final pump = AlarmKitActionPump(
    host: alarmKit,
    apply: onEvent,
    log: ref.watch(alarmLogProvider),
  );

  // A receipt guards against a redelivery from the native queue, which never
  // holds an action this long.
  unawaited(
    db
        .pruneActionReceipts(
          olderThan: DateTime.now().toUtc().subtract(const Duration(days: 30)),
        )
        .then<void>((_) {}, onError: (Object _) {}),
  );

  final ask = ref.read(alarmPermissionAskProvider.notifier);
  // The ring overlay reads what this scheduler saw and changed on the
  // AlarmKit lane (#46). A microtask, for the same reason as the permission
  // ask below; a container already gone has nobody left to tell.
  final observedAlarmKit = AlarmKitViewHost(
    alarmKit,
    onView: (rows) => scheduleMicrotask(() {
      try {
        ref.read(alarmKitViewProvider.notifier).replace(rows);
      } on Object {
        // Signed out or torn down.
      }
    }),
  );

  final scheduler = NotificationScheduler(
    gateway: gateway,
    alarmKit: observedAlarmKit,
    // A microtask, because `start()` below runs inside this provider's build
    // and Riverpod refuses a write to another provider from there. The order
    // of begin/end is kept: microtasks run first-in, first-out.
    onPermissionAsk: (asking) => scheduleMicrotask(() {
      try {
        asking ? ask.begin() : ask.end();
      } on Object {
        // The container is gone (signed out, test torn down): nothing to hide.
      }
    }),
    // The one gate (OPH-446): off and unknown plan every urgent alarm as an
    // ordinary notification, on and legacy ring as before.
    alarms: gateAlarms(
      ref.watch(reminderStoreProvider).watchAlarmsIn(scope),
      gate.stream,
    ),
    privacyMode: ref.watch(notificationPrivacyProvider),
    log: ref.watch(alarmLogProvider),
    profile: ref.watch(reminderProfileProvider),
    sounds: ref.watch(alarmSoundResolverProvider),
    alarmSound: ref.watch(alarmSoundChoiceProvider),
    reminderSound: ref.watch(reminderSoundChoiceProvider),
    // The AlarmKit alert has room for ONE snooze button (OPH-182), so it offers
    // whichever the user put first in their own order.
    snoozePreset: ref.watch(snoozePresetOrderProvider).first,
    // Round 19 K3: NOTIFICATIONS §2 has always said the window re-fills "on
    // every app foreground", and nothing was doing it — the plan only ever
    // moved when the replica emitted. Injected rather than reached for inside
    // the scheduler so a pure scheduler test needs no `WidgetsBinding`.
    onForeground: (onResume) {
      final listener = AppLifecycleListener(
        onResume: () {
          onResume();
          // Every resume pulls (§2b.3), also where no AlarmKit pass runs.
          unawaited(pump.pull());
        },
      );
      return listener.dispose;
    },
    // The plan pass pulls and applies first, so a native snooze is in the
    // model before the plan judges the alarm it left behind (OPH-426); a
    // fallback notification goes once a later plan rang the alarm itself.
    drainActions: pump.beforePlan,
    afterPlan: pump.afterPlan,
    appliedEventIds: () async => {
      for (final r in await db.select(db.actionReceipts).get()) r.eventId,
    },
  );
  unawaited(scheduler.start());
  ref.onDispose(scheduler.dispose);

  final responses = gateway.events.listen(onEvent);
  ref.onDispose(responses.cancel);
  // AlarmKit presses are PULLED (§2b.3): one pull when this listener attaches,
  // one per native `onActionsPending`; each is acked only after its commit.
  final alarmKitPending = alarmKit.actionsPending.listen(
    (_) => unawaited(pump.pull()),
  );
  ref.onDispose(alarmKitPending.cancel);

  return scheduler;
});
