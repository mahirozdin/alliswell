# TASKS — AllisWell backlog

> **How to use:** this file holds **open work only**, in order — the first task below without ⏸️
> is the **next task**. Don't read the file whole to find it: `npm run next` prints it with its
> epic's intro (`-- --list` for everything ready, `-- --summary` for the counts). The pointer also
> lives in [STATE.md](STATE.md), and `check:docs` keeps the two equal. Rules and workflow:
> [../AGENTS.md](../AGENTS.md). Spec: [BLUEPRINT.md](BLUEPRINT.md). Traps and decisions by area:
> [LESSONS.md](LESSONS.md) (grep the area, don't read it whole).
>
> **Format** (read by `scripts/tasks/tasks.mjs`): `## Epic NN — …` sections, `### OPH-NNN — …`
> tasks, `- [ ]` boxes. **⏸️ in a task heading** = it waits on the owner (an account, a console, a
> store review): it is never picked, STATE must name it, and removing the ⏸️ puts it back in the
> queue. Order is dependency — a task that needs a parked one is parked too.
>
> **A closed task is deleted, not ticked** — its record is git history and the CHANGELOG, and
> `npm run check:docs` fails on a closed task left behind. Before deleting it: a trap that can
> silently recur → LESSONS.md; an owner decision → STATE.md. Every task up to Epic 33
> (OPH-001…OPH-350), with its full notes, is in `git show 85b6c1b:docs/TASKS.md`.

---

## Epic 35 — Design and UX round (persona + Mobbin review)

Sahip isteği (2026-11-07): tasarım baştan değişmeden core'da UI, UX ve tipografi iyileşsin; landing ve
GitHub ilk ekranı güçlensin. Bulgular, ölçümler ve bulgu kimlikleri (R-xx kabuk, A-xx Android probe,
T-xx tipografi, K-xx landing, N-xx/D-xx GitHub, CT-xx rakip; E-xx/U-xx persona) →
[research/2026-11-design-ux/README.md](research/2026-11-design-ux/README.md). Ayrıntıyı oradan oku,
burada tekrar yok. **Sahip kararları (2026-11-07, STATE'te):** telefon alt barı B+ (eşit 5 yuva, hepsi
etiketli, 64 pt kapsül, sağda mikrofon + "+" kümesi, Hızlı Erişim balonu telefonda varsayılan kapalı —
[ADR-0062](adr/0062-phone-navigation-equal-slot-labelled-capsule.md)); acil alarm varsayılanı açık kalır
(DESIGN §26 C1); landing H1 alarm, alt başlık self-host + Claude/ChatGPT MCP; font ailesi değişmez
([ADR-0063](adr/0063-platform-tracking-glass-type-v1-one-formatter.md)); lisans değişmez, "open source"
ifadeleri kalkar (source-available); ton: core "sen", uzantı/portal/landing/kurumsal "siz"; mikrofon AI
sağlayıcısı yokken dikte; Fikirler/Inbox adları kalır, ikon ampul; herkese açık demo ve landing ölçümü
sonraki tur. Sıra bağımlılıktır. Her iş: test önce, K1, belge, hata düzeltmesinde regresyon testi.
Görsel değişiklikte golden matrisi gerektiği kadar: genişlik 360/375/393/412/430 × metin ölçeği
1.0/1.3/2.0 × TR/EN × koyu/açık. Sürüm, etiket, deploy, GitHub ayarı ve mağaza yüklemesi sahibin.

---

## Epic 36 — Alarms that silence, ring once per minute and on the chosen device; widget day views (#46–#50, PR-1)

Issues #46 (ring-screen actions did not silence; misaligned layout), #47 (same-minute urgent alarms
overlap), #48 (every signed-in device rings), #49 (the AlarmKit alert's Ertele did nothing) and the
day-view half of #50 (the widget showed yesterday's list). Owner decisions of 2026-11-12 are in
STATE "Sahip kararları". Binding text: [ADR-0068](adr/0068-urgent-alarms-in-one-minute-ring-as-one.md),
[ADR-0069](adr/0069-urgent-alarm-device-is-a-server-flag.md), the 2026-11-12 revisions of ADR-0015
and ADR-0010, and the AlarmKit channel contract in [NOTIFICATIONS.md](NOTIFICATIONS.md) §2b.3 — the
Dart and Swift lanes both implement it; where a task and §2b.3 differ, §2b.3 wins. Not in this epic
(candidates): iOS BGAppRefresh and silent push, a refresh lease, WidgetKit push, remote stop of a
ringing iPhone, macOS widget self-fetch.
This epic's docs and §2b.3 are committed before any lane starts, and every lane starts from that
commit. Waves: **W1** OPH-421…438 (silence works) → **W2** OPH-439…451 + OPH-466/467 (one ring per
minute, ring screen direction A, Devices) → **W3** OPH-452…456 (wiring and close). Inside a wave the lanes run in
parallel (dart-a, dart-b, dart-c, swift, api, wire) and each lane keeps its order. Shared fixtures
are born in the Dart lane; Swift and the API only read them. Swift tests run on the Mac:
`xcodebuild test -only-testing:RunnerTests` (iOS 27.2 simulator) + `flutter build ios --simulator
--debug`. Each commit body carries `Changelog:` and `Device:` lines; the shared docs are written
once, in OPH-456. Every new native call degrades to today's path where it is missing (Android, web,
desktop, an old server). No Dart or Swift lane runs `apps/api` integration suites (one shared
MySQL); they run in the main checkout. Version, tag, deploy and store uploads belong to the owner.

### OPH-421 — Replica schema v40: local `action_receipts` table

Kritik yol: sync. W1 · dart-a · #49.

- [ ] Drift table `action_receipts` (`event_id` TEXT PK, `action`, `applied_at` UTC ms) in
      `apps/app/lib/src/sync/db/database.dart`; `schemaVersion` 39 → 40, a `from < 40` step that
      creates only this table; `insertReceiptIfAbsent` (INSERT OR IGNORE, true only when inserted,
      works inside the caller's transaction) and `pruneActionReceipts(olderThan)`; regenerate
      `database.g.dart`.
- [ ] Local only: never in the sync field list, the outbox or the pull loader. No other table.
- **Acceptance:** a v39 database upgrades with every synced table unchanged; the receipt is true
  once per event and rolls back with its transaction; `check:sync-fields` unchanged.
- **Test first:** `test/sync/migration_test.dart` → 'v39 → v40 adds action_receipts without
  touching synced tables'.
- **Verify:** `npm run verify:task -- apps/app/test/sync/migration_test.dart
  apps/app/test/notifications/action_receipts_test.dart` · `npm run check:sync-fields` · `flutter
  analyze`. The sync rule's K1 extra (`apps/api/test/integration/sync.test.js`) runs at the W1
  integration in the main checkout, not in the lane.

### OPH-422 — Shared Turkish locative helper for time and device suffixes

Kritik yol: push-notifications. W1 · dart-a · #46.

- [ ] Pure `apps/app/lib/src/core/tr_locative.dart`: `trLocative` (’da/’de/’ta/’te by the last
      spoken number of a clock time, by vowel harmony and the hard-consonant rule for a word, a
      trailing number by the number rule) and `awAt(value, languageCode)`.
- [ ] `alarm.snoozeRingsAt` and `alarm.snoozeConfirmed` take the suffixed value; every other
      `{placeholder}’suffix` key in `tr.json` converts the same way; every new key of this epic
      that suffixes a time or device name uses the helper.
- **Acceptance:** no `tr.json` value hard-codes a suffix after a placeholder; English unchanged.
- **Test first:** `test/core/tr_locative_test.dart` → clock times (09:05’te, 09:30’da, 09:00’da,
  13:40’ta, 00:00’da) and device names (iPhone 16’da, MacBook Air’de).
- **Verify:** `npm run verify:task -- apps/app/test/core/tr_locative_test.dart
  apps/app/test/notifications/alarm_ring_screen_test.dart` · `npm run check:i18n` · `flutter analyze`.
- **Device:** Turkish UI — tiles and the confirmation read "09:05’te çalar" / "09:30’da tekrar çalacak".

### OPH-423 — Ring screen: one sound owner, silence → dismiss → write, keyed screen

Kritik yol: push-notifications. W1 · dart-a · #46.

- [ ] `AlarmOverlayController` becomes the only owner of `AlarmFeedback` (state `ringing` +
      `silentHere`; `silence()`, `startSound()`); the screen never starts or stops sound.
- [ ] Every action: `silence()` synchronously → dismiss → await the write. A failed write re-shows
      the occurrence with a `failed` flag: the screen opens with an inline error (`alarm.actionFailed`
      "Kaydedilemedi. Ses durdu, tekrar dene." + `alarm.retry` "Tekrar dene"), no snackbar, and the
      controller does not restart the sound for it — only the 60 s no-interaction rule (OPH-441)
      does. Buttons are never built disabled; a second tap while busy is ignored.
- [ ] Screen keyed `ValueKey('<taskId>|<fireAtMs>')`; `_handled` keyed the same, so a snoozed alarm
      rings again in the same session. Existing button keys stay.
- **Acceptance:** all nine actions stop the feedback before any await and close the screen.
- **Test first:** `test/notifications/alarm_ring_screen_test.dart` → 'acting on the first of two due
  alarms leaves the second fully actionable'; `test/notifications/alarm_overlay_test.dart` → 'a
  failed write re-shows the alarm silently with the error'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarm_ring_screen_test.dart
  apps/app/test/notifications/alarm_overlay_test.dart apps/app/test/notifications/missed_alarm_card_test.dart`
  · `npm run check:notify-matrix && npm run check:push-payload` · `flutter analyze`.
- **Device:** D-46a — iPhone and Android, two urgent alarms in one minute: every button silences
  within 1 s; the second screen is fully tappable.

### OPH-424 — AlarmKit occurrence id and fingerprint with shared fixtures

Kritik yol: push-notifications. W1 · dart-a · #49.

- [ ] Pure `apps/app/lib/src/notifications/alarmkit_identity.dart` with `alarmKitFireAtMs`,
      `alarmKitOccurrenceId`, `alarmKitFingerprint` exactly as NOTIFICATIONS §2b.3 (reuse
      `notificationIdFor`); `AlarmKitAlarm` gains `members` and `fp`; `planAlarmKitAlarms` uses
      members = [taskId] (grouping is OPH-440).
- [ ] Fixtures born here (written with `UPDATE_FIXTURES=1`, compared otherwise):
      `apps/app/test/fixtures/alarmkit_identity_cases.json`, `snooze_preset_cases.json`; extract
      `snoozeUntilWallClock(preset, nowWall)` that `TaskStore.snoozeUntilFor` delegates to (no
      behaviour change). No snooze-target shifting in Dart.
- **Acceptance:** ids depend only on sorted unique task ids and the second-floored instant; both
  fixtures byte-stable across two runs.
- **Test first:** `test/notifications/alarmkit_identity_test.dart` → 'occurrence id and fingerprint
  match the shared fixture'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarmkit_identity_test.dart
  apps/app/test/notifications/snooze_preset_parity_test.dart apps/app/test/notifications/planner_test.dart
  apps/app/test/notifications/scheduler_test.dart` · `npm run check:notify-matrix && npm run
  check:push-payload` · `flutter analyze`.

### OPH-425 — AlarmKit channel contract v2 on the Dart side

Kritik yol: push-notifications. W1 · dart-a · #49.

- [ ] Implement NOTIFICATIONS §2b.3 as committed; edit it only for a real gap, in the same commit.
- [ ] `AlarmKitHost`, `UnsupportedAlarmKitHost`, `MethodChannelAlarmKitHost` gain `scheduledAlarms`,
      `stop`, `pullPendingActions`, `ackActions`, `clearFallbacks`, `pullFailures` and
      `Stream<void> actionsPending`; the constructor drain and pushed events go, except the legacy
      path of §2b.3 (macOS, an old native side). `copyNativeFailures(AlarmLog)` records `degraded`,
      lane `alarmkit`.
- **Acceptance:** nothing is pushed down the channel, Dart pulls; a native side without
  `scheduledAlarms` degrades to `scheduledIds`; Android/web/desktop behave as before.
- **Test first:** `test/notifications/alarmkit_test.dart` → 'actions queued before the listener
  exists are delivered after it attaches'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarmkit_test.dart
  apps/app/test/notifications/scheduler_test.dart` · `npm run check:notify-matrix && npm run
  check:push-payload && npm run check:docs` · `flutter analyze`.

### OPH-426 — Scheduler AlarmKit pass: occurrence validity, stop superseded, never cancel a ringing alarm

Kritik yol: push-notifications. W1 · dart-a · #49.

- [ ] Pure `planAlarmKitPass(desired, current, alarms, appliedEventIds, now, staleWindow)` →
      toStop/toCancel/toSchedule/toReschedule, per the plan-pass rule of §2b.3; the scheduler runs
      an injected `drainActions` first, executes and logs; the accepted set counts every member.
- [ ] Keep the per-pass authorization re-read and the over-limit logging; the notification-lane
      set-diff is unchanged.
- **Acceptance:** a ringing alarm is never `cancel`ed; a superseded one is `stop`ped; after a native
  snooze and its drained event exactly one alarm exists for the new instant.
- **Test first:** `test/notifications/scheduler_test.dart` → 'moving an urgent task from 09:00 to
  10:00 replaces its AlarmKit alarm and leaves nothing at 09:00'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/scheduler_test.dart
  apps/app/test/notifications/planner_test.dart apps/app/test/notifications/alarmkit_test.dart` ·
  `npm run check:notify-matrix && npm run check:push-payload` · `flutter analyze`.
- **Device:** D2 — after a native snooze it rings once; opening the app adds no second alarm.
  D3 — a plan pass never touches a still-current alerting alarm.

### OPH-427 — Pulled actions applied exactly once; native `untilMs` kept

Kritik yol: push-notifications. Kritik yol: sync. W1 · dart-a · #49.

- [ ] `NotificationEvent` gains `eventId`, `taskIds`, `untilMs`, `occurrenceFireAtMs`, `origin`,
      `lane`; `handleNotificationEvent` applies one event in one transaction: receipt → model write
      → outbox; a duplicate is a no-op. An `alarmkit` snooze writes `untilMs` unchanged.
- [ ] `TaskStore.snooze/complete/muteAlarms` and `ReminderStore.acknowledge` take an optional
      `receiptId` and work inside the caller's transaction; a UI tap without it is unchanged.
      Notification-lane `eventId` = `<notificationId>|<actionId>|<deliveryTimestamp>`.
- [ ] Wiring in `notifications/providers.dart`: pull on attach, `actionsPending` and resume → apply
      in `pressedAtMs` order → ack after commit → `copyNativeFailures` → `clearFallbacks` after the
      next plan; prune receipts older than 30 days at start.
- [ ] A converted v1 `snooze:<preset>` entry (`preset`, no `untilMs`; queued by v1.19.2) gets its
      target from `snoozeUntilWallClock(preset, pressedAt)` and is applied once. Test: 'a converted
      v1 snooze:<preset> entry is applied once with the preset target'.
- **Acceptance:** any number of redeliveries raise `snoozeCount` once with one outbox mutation per
  task; the row shows "Ertelendi — HH:MM" with the press-time target.
- **Test first:** `test/notifications/actions_test.dart` → 'a snooze redelivered after a crash
  between commit and ack is applied exactly once'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/actions_test.dart
  apps/app/test/notifications/alarmkit_test.dart apps/app/test/notifications/reminder_store_test.dart
  apps/app/test/notifications/scheduler_test.dart apps/app/test/sync/migration_test.dart` · `npm run
  check:notify-matrix && npm run check:push-payload` · `flutter analyze`.
- **Device:** D1/D4 — native Ertele killed/background/foreground, locked/unlocked; after opening the
  app the task says "Ertelendi — HH:MM" and the log has one alarmkit action row.

### OPH-428 — In-app actions stop the ringing AlarmKit alarm; no second sound

Kritik yol: push-notifications. W1 · dart-a · #46.

- [ ] Expose the last `scheduledAlarms` view through a provider. An occurrence covered by an
      AlarmKit alarm opens the screen with `silentHere` (no in-app sound, line
      `alarm.ringingOnLockScreen`).
- [ ] Every in-app action calls `host.stop(id)` for the alerting record(s) of that occurrence right
      after `silence()`, fire-and-forget; a failure is logged `degraded` and never blocks the
      dismissal. Without AlarmKit the path is unchanged.
- **Acceptance:** on iOS 26+ an in-app action silences the app and the system alert.
- **Test first:** `test/notifications/alarm_overlay_test.dart` → 'an in-app snooze stops the
  alerting AlarmKit alarm of that occurrence'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarm_overlay_test.dart
  apps/app/test/notifications/alarm_ring_screen_test.dart apps/app/test/notifications/alarmkit_test.dart`
  · `npm run check:notify-matrix && npm run check:push-payload` · `flutter analyze`.
- **Device:** D-46b — iPhone, app open while the AlarmKit alert rings: one sound; 5 dk in the app
  silences the alert too.

### OPH-429 — `AWAlarmIdentity` (FNV-1a over UTF-16) and the RunnerTests target

W1 · swift · #49.

- [ ] `ios/Shared/AWAlarmIdentity.swift`: `fnv1a`, `occurrenceId(members:fireAtMs:)`,
      `fingerprint(...)`, `fireAtMs(_:)` per §2b.3; no AlarmManager code (the macOS widget compiles
      `ios/Shared`); `uuid(for:)` unchanged.
- [ ] Add the file to Runner and the widget extension and create the RunnerTests target through
      `ios/scripts/wire_alarmkit.rb` (idempotent; never hand-edit `project.pbxproj`).
- **Acceptance:** every fixture case gives the Dart id and fp (Turkish letters, emoji included);
  running the wire script twice changes nothing the second time.
- **Test first:** `ios/RunnerTests/AlarmIdentityTests.swift` → `testOccurrenceIdMatchesDartFixture`
  (the fixture comes from the dart-a branch, read-only here). Starts only after OPH-424 is
  committed; the Mac run pushes the dart-a branch too and checks the fixtures out of it.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator --debug`.

### OPH-430 — `AWAlarmLedger` and the v2 channel methods in `AlarmKitBridge`

W1 · swift · #49.

- [ ] `ios/Shared/AWAlarmLedger.swift` (injected `UserDefaults`, key `aw.alarmkit.ledger`, pruned
      against `AlarmManager.shared.alarms`); bridge methods `scheduledAlarms`, `scheduledIds`
      (derived), `schedule` (ledger + both intents), `cancel`, `stop`, `pullPendingActions`,
      `ackActions`, `clearFallbacks`, `pullFailures`; `drainPendingActions` stays a no-op;
      `onActionsPending` replaces the pushes.
- [ ] `AWAlarmActionQueue` stores v2 entries (v1 rewritten on read; a v1 snooze keeps its `preset`,
      `testV1SnoozeKeepsPreset`); `AWWidgetCompleteIntent` enqueues v2; the macOS bridge (`macos/Runner/MainFlutterWindow.swift`) reads v2 entries on its legacy
      drain (§2b.3). Fix the stale "§8" comment in `AlarmKitBridge.swift`.
- **Acceptance:** no queued action is removed before Dart acks it; an old Dart loses nothing; a
  macOS widget completion still reaches the app.
- **Test first:** `ios/RunnerTests/AlarmLedgerTests.swift` → `testQueueKeepsEntriesUntilAcked`.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator
  --debug` (+ `flutter build macos` when the Mac can sign it, else NOT RUN).

### OPH-431 — Native snooze and stop intents: always stop, schedule natively, fallback, never throw

W1 · swift · #49.

- [ ] `ios/Shared/AWSnoozeCore.swift`: `AWAlarmOps` protocol + pure `AWSnoozeCore.run` doing the
      native-snooze steps of §2b.3 (base target only; +1 min is OPH-450).
- [ ] `AWAlarmSnoozeIntent` / `AWAlarmStopIntent` take the §2b.3 parameters (legacy `taskId`,
      `reminderId` optional); `.background`, `openAppWhenRun = false`, `.alwaysAllowed`; never
      throw. `.custom` stays (ADR-0015 §9). Fix the stale `.countdown` comment.
- [ ] Legacy rule of §2b.3 (alarms scheduled by v1.19.2 keep v1 intents after an update): no
      `alarmId` → stop every `.alerting` alarm in our namespace, skip the native schedule (`failed`,
      `legacy-intent`), add the fallback. Test `testLegacyIntentWithoutAlarmIdStopsAlertingAlarms`.
- **Acceptance:** Ertele silences in every injected failure combination; a failed schedule leaves
  one fallback notification; Durdur still reaches Dart.
- **Test first:** `ios/RunnerTests/SnoozeCoreTests.swift` →
  `testMaximumLimitReachedStillStopsAndAddsFallbackNotification`.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator --debug`.
- **Device:** D1 (force-quit/background/foreground × locked/unlocked: silent at once), D2 (rings
  once; two snoozes leave one alarm), D4 (before first unlock), D5 (Durdur and the hardware key).

### OPH-432 — Migration: `notification_devices.rings_urgent` + source, backfill

Kritik yol: migrations. W1 · api · #48.

- [ ] `apps/api/migrations/20261112120000_add_notification_device_rings_urgent.js`: `rings_urgent`
      BOOLEAN NOT NULL DEFAULT 0, `rings_urgent_source` VARCHAR(16) NULL; honest `down()`.
- [ ] Exported `backfillRingsUrgent(knex, {now})`: per user the oldest non-web device seen in 14
      days, else the oldest web device seen in 14 days, else the oldest device (ties by id) → 1;
      every row of that user `source = 'backfill'` (ADR-0069 #4). MySQL 8 and MariaDB; no collation pin.
- **Acceptance:** migrate → rollback → migrate is clean; every user with devices has exactly one
  ringing row.
- **Test first:** `apps/api/test/integration/notification-devices-backfill.test.js` → 'backfill
  rings the first-added device seen in the last 14 days and silences the rest'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/notification-devices-backfill.test.js
  apps/api/test/integration/notification-devices.test.js apps/api/test/unit/notification-devices.test.js`.
- **Device:** D-48e — an updated install keeps ringing when it is the first-added recent device.

### OPH-433 — Urgent-device rule on PUT, PATCH, promotion on DELETE, `ringsUrgent` in responses

W1 · api · #48.

- [ ] `apps/api/src/db/notification-devices.js` holds the ADR-0069 #2 rule, applied on insert or
      takeover with the user row `FOR UPDATE`; a heartbeat never touches the flag.
- [ ] New `PATCH /notification-devices/:deviceId {ringsUrgent?, deviceName?}` (own rows only, else
      404 `DEVICE_NOT_FOUND`; source `user`; last one off → `warnings: ['NO_URGENT_DEVICE']`; blank
      name → platform label). DELETE stays 204 and promotes. Responses add `ringsUrgent`,
      `ringsUrgentSource`; `npm run api:docs`. No #47 minute rule, no 409.
- I-12: REST only; MCP not extended — device infrastructure, not task data.
- **Acceptance:** never two auto-chosen ringing devices; old clients keep working.
- **Test first:** `apps/api/test/integration/notification-devices.test.js` → 'web first then a phone
  leaves exactly one ringing device, the phone'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/notification-devices.test.js
  apps/api/test/unit/notification-devices.test.js apps/api/test/integration/notification-devices-backfill.test.js`
  · `npm run check:openapi && npm run check:apidocs && npm run check:postman && npm run check:no-ee`.
- **Device:** D-48a — web first, then iPhone: only the iPhone rings.

### OPH-434 — Bind a session family to its device: `refresh_tokens.device_id`

Kritik yol: auth. Kritik yol: migrations. W1 · api · #48.

- [ ] `apps/api/migrations/20261112130000_add_refresh_token_device_id.js`: `device_id` CHAR(26) NULL
      + index (user_id, device_id); no backfill; honest `down()`.
- [ ] Optional `deviceId` (ULID, else 400) on login, register, oauth, every sign-in door and
      `/auth/refresh`; `createRefreshRecord({deviceId})`; rotation copies it; a bound family keeps its
      binding. Body schemas stay strict, only the property is added.
- I-12: REST only (a session detail, not a user capability); MCP unchanged.
- **Acceptance:** a client that never sends `deviceId` behaves as before; the binding is set once.
- **Test first:** `apps/api/test/integration/auth-refresh.test.js` → 'refresh with deviceId binds
  the family to that device'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/auth.test.js
  apps/api/test/integration/auth-refresh.test.js apps/api/test/integration/auth-me.test.js
  apps/api/test/integration/sessions.test.js apps/api/test/integration/mfa.test.js` · `npm run
  check:openapi && npm run check:apidocs && npm run check:postman`.

### OPH-435 — Real remote sign-out: DELETE a device revokes its session family

Kritik yol: auth. W1 · api · #48.

- [ ] `DELETE /notification-devices/:deviceId` (own row): revoke the families bound to it, delete
      the row, promote (OPH-433) — one transaction; a foreign or missing id revokes nothing, 204.
      The app's own sign-out (DELETE then `/auth/logout`) must still succeed.
- [ ] Reverse: `dropDevicesOfFamilies(trx, userId, familyIds)` from session revoke, revoke others,
      reuse, password change and logout-all. GET adds `hasSession`. Route comment states the
      access-token TTL limit. `npm run api:docs`.
- I-12: REST only; removing a device is delete-like and never enters MCP.
- **Acceptance:** a removed device is signed out at its next refresh and gets no more pushes.
- **Test first:** `apps/api/test/integration/notification-devices-signout.test.js` → 'deleting a
  device revokes every live family bound to it and removes the row'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/notification-devices-signout.test.js
  apps/api/test/integration/notification-devices.test.js apps/api/test/integration/auth.test.js
  apps/api/test/integration/auth-refresh.test.js apps/api/test/integration/auth-me.test.js
  apps/api/test/integration/sessions.test.js apps/api/test/integration/mfa.test.js` · `npm run
  check:openapi && npm run check:apidocs && npm run check:postman && npm run check:no-ee`.
- **Device:** D-48d — remove Android from the iPhone: within 15 min Android is signed out and wiped.

### OPH-436 — Android wake on task and project changes; urgent acknowledge bypasses the minute gate

Kritik yol: push-notifications. W1 · api · #48, #50.

- [ ] `plugins/push-wake.js` admits `task` and `project` changes for the existing per-workspace-minute
      wake; recipients stay Android FCM (no iOS, ADR-0038 §8).
- [ ] An urgent reminder snoozed, or acknowledged/completed/cancelled within [now − 45 min, now +
      1 min], enqueues an alarm-stop wake past the gate (job key `alarm-stop:<reminderId>:<updated_at
      ms>`) to the workspace members' Android devices with `rings_urgent = 1`. Payload stays
      `{v: 1, type: 'wake'}`; sync routes untouched.
- **Acceptance:** an answered alarm always reaches the other ringing Android devices; payload and
  platforms unchanged; `check:push-payload` green without `--write`.
- **Test first:** `apps/api/test/unit/push-wake.test.js` → 'an acknowledged urgent reminder in its
  ring window wakes even when the minute was already used'.
- **Verify:** `npm run verify:task -- apps/api/test/unit/push-wake.test.js
  apps/api/test/integration/push-alarm-stop.test.js apps/api/test/unit/push-transport.test.js
  apps/api/test/unit/push-payload.test.js` · `npm run check:push-payload && npm run check:notify-matrix`.
- **Device:** D-50a — Android widget shows a web change within minutes; D-48c — with OPH-445, B stops
  when A acknowledges (also in Doze).

### OPH-437 — Widget snapshot v6: per-day views for today + 2 days and a stale state

W1 · dart-c · #50.

- [ ] `widget_snapshot.dart`: version 5 → 6; `WidgetDayView` {date, header, openToday,
      openTodayLabel, next, buckets with that day's events, views per project}; `days` = today + 2;
      top-level fields equal day 0 (ADR-0010 revision 2026-11-12).
- [ ] Day d uses the same `_listData` and project loop; completed rows only when completed on or
      after that day's start; new `strings.stale` (`widget.stale`). Set `kWidgetSnapshotMaxBytes`
      from a measurement (300 tasks, 20 projects). No iOS background path.
- **Acceptance:** day 0 equals the v5 view in meaning; a v5 reader still renders.
- **Test first:** `test/features/widgets/widget_midnight_test.dart` → "tomorrow's day view has its
  own Today list, open count, next task and project views".
- **Verify:** `npm run verify:task -- apps/app/test/features/widgets/widget_midnight_test.dart
  apps/app/test/features/widgets/widget_core_test.dart apps/app/test/features/widgets/widget_events_test.dart
  apps/app/test/features/widgets/widget_lists_test.dart apps/app/test/features/widgets/widget_private_test.dart`
  · `npm run check:i18n` · `flutter analyze`.

### OPH-438 — Write and reload the widget on background; interactivity callback after the App Group

W1 · dart-c · #50.

- [ ] On paused/hidden, `widgetSyncProvider` writes the last snapshot and reloads the timelines
      (lifecycle hook inside `features/widgets`).
- [ ] Register `HomeWidget.registerInteractivityCallback` only on Android, or on iOS after the App
      Group is configured (`homeWidgetCallbackSupported`); Android unchanged.
- **Acceptance:** the widget is never older than the last app session; no `-7` error on iOS.
- **Test first:** `test/features/widgets/widget_background_write_test.dart` → 'going to the
  background writes the snapshot and requests a widget reload'.
- **Verify:** `npm run verify:task -- apps/app/test/features/widgets/widget_background_write_test.dart
  apps/app/test/features/widgets/home_widget_platform_test.dart
  apps/app/test/features/widgets/android_background_receiver_test.dart` · `flutter analyze`.
- **Device:** D11 — background the app: newest list, no home_widget -7; Android widget tap works.

### OPH-439 — `TaskStore.snoozeBatch` and `ReminderStore.acknowledgeBatch`

Kritik yol: push-notifications. Kritik yol: sync. W2 · dart-a · #47.

- [ ] `snoozeBatch(taskIds, {until, receiptId?})`: one transaction, receipt first, ids de-duplicated,
      every active reminder `snoozeCount + 1` exactly once, one outbox mutation per task; `snooze`
      becomes its one-element wrapper (fixes the double increment when remind and due share a minute).
- [ ] `acknowledgeBatch(taskIds, {occurrenceMinute, receiptId?})`; `actions.dart` applies a
      `taskIds` event through the batch calls. A target in an occupied minute is written unchanged
      (ADR-0068 #5).
- I-12: no REST/MCP change — owner decision 2026-11-12 (no server rule for #47).
- **Acceptance:** a group action is one receipt, one transaction, one mutation per task.
- **Test first:** `test/features/tasks/task_store_snooze_batch_test.dart` → 'snoozeBatch dedupes
  task ids and writes one outbox mutation per task'.
- **Verify:** `npm run verify:task -- apps/app/test/features/tasks/task_store_snooze_batch_test.dart
  apps/app/test/notifications/reminder_store_test.dart apps/app/test/notifications/actions_test.dart
  apps/app/test/features/tasks/tasks_flow_test.dart` · `npm run check:notify-matrix && npm run
  check:push-payload` · `flutter analyze`.

### OPH-440 — One AlarmKit alarm and one notification chain per UTC minute

Kritik yol: push-notifications. W2 · dart-a · #47.

- [ ] `planAlarmKitAlarms` groups urgent occurrences by UTC minute: one alarm, members = sorted
      unique task ids, earliest instant; title = the task, or `alarm.groupTitle` ("{count} acil
      alarm") for several (privacy mode as today). Occurrence validity compares by minute.
- [ ] `planNotifications`: same-minute urgent chains merge into one (payload ids only, body
      `urgentMany(n)`); Android gets one full-screen intent and its actions one batch event.
- I-12: no REST/MCP change — grouping lives on the device (ADR-0068 #4).
- **Acceptance:** three urgent alarms at 09:00 → one AlarmKit alarm and one chain; single-member
  minutes keep their OPH-424 id.
- **Test first:** `test/notifications/planner_test.dart` → 'urgent alarms sharing a minute become one
  AlarmKit alarm with every task id'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/planner_test.dart
  apps/app/test/notifications/scheduler_test.dart apps/app/test/notifications/gateway_replay_test.dart
  apps/app/test/notifications/actions_test.dart` · `npm run check:notify-matrix && npm run
  check:push-payload` · `flutter analyze`.
- **Device:** D6 — three alarms at 09:00 (one from another device): one sound, one "3 acil alarm"
  alert; Android one full-screen notification.

### OPH-441 — Overlay lists every alarm ringing in the minute; group actions as one batch

Kritik yol: push-notifications. W2 · dart-a · #47.

- [ ] `AlarmOverlayState.ringing` = every urgent alarm ringing now; a newcomer joins without a
      second sound; one feedback for the list.
- [ ] `actOnRow(taskId, action)`, `snoozeAll(until)`, `acknowledgeAll()` — each one `inapp` event
      through `handleNotificationEvent` with a receipt. The first action silences and stops the
      covering AlarmKit alarm; the screen stays while rows remain; 60 s without interaction resumes
      the in-app sound only.
- **Acceptance:** never two in-app sounds; synced and older alarms in the minute join the list.
- **Test first:** `test/notifications/alarm_overlay_test.dart` → 'three urgent alarms in one minute
  ring as one screen listing all three'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarm_overlay_test.dart
  apps/app/test/notifications/alarm_ring_screen_test.dart apps/app/test/notifications/actions_test.dart`
  · `npm run check:notify-matrix && npm run check:push-payload` · `flutter analyze`.

### OPH-442 — Pure `urgentAlarmsInMinute` and the "rings with another alarm" snooze line

Kritik yol: push-notifications. W2 · dart-a · #47.

- [ ] Pure `apps/app/lib/src/notifications/urgent_minute.dart`: `urgentAlarmsInMinute(alarms, at,
      {exceptTaskIds})` counts other tasks' active urgent occurrences in that UTC minute
      (acknowledged, muted and normal reminders do not count); `snoozeTileSubline(until,
      joinsGroup:)` → `alarm.snoozeRingsAt` or `alarm.snoozeJoinsGroup` ("09:05’te çalar · başka
      alarmla birlikte") through the locative helper. No UI here: the tile is OPH-466, the form
      line OPH-444.
- **Acceptance:** pure, no Flutter dependency; the Turkish line reads as above.
- **Test first:** `test/notifications/urgent_minute_test.dart` → 'same task never counts itself;
  acknowledged, muted and normal reminders do not count'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/urgent_minute_test.dart
  apps/app/test/core/tr_locative_test.dart` · `npm run check:i18n` · `flutter analyze`.

### OPH-466 — Ring screen direction A: equal-width grid, full-width Onayla, pressed, error, keyboard

Kritik yol: push-notifications. W2 · dart-a · #46.

- [ ] Single layout: content on top (badge 96, time, title ≤ 3 lines, meta), action block pinned at
      the bottom: "Ertele" label, one 2-column grid of a new `AwAlarmActionTile` (56, presets in the
      user's order + "Saat seç…" + "Süresiz ertele" with "Görev açık kalır, alarm çalmaz"), Onayla
      full grid width (56), Tamamla | Aç (48). Width ≤ 440, centred on wide screens.
- [ ] Under 700 pt high: badge 64, title ≤ 2 lines, label hidden; text scale > 1.3: one column and
      the screen scrolls. Pressed: silence first, overlay + 0.97 scale (overlay only with reduced
      motion), haptic, spinner after 300 ms; nothing looks disabled. The failed state of OPH-423 is
      only styled here (inline error above the actions, sound off). Tile line 2 from OPH-442.
      Keyboard: Enter = Onayla, 1–4 presets. Directions B and C are not built.
- **Acceptance:** tiles and Onayla share one width; `check:fab`, `check:opacity`, `check:typography`
  green; taps 56/56/48.
- **Test first:** `test/notifications/alarm_ring_screen_test.dart` → 'snooze grid cells share one
  width at 320 and 430 logical px'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarm_ring_screen_test.dart
  apps/app/test/notifications/alarm_overlay_test.dart apps/app/test/notifications/missed_alarm_card_test.dart`
  · `npm run check:fab && npm run check:opacity && npm run check:typography && npm run check:i18n`
  · `flutter analyze`.
- **Device:** D-46c — 320/393/430 wide, 360×640 and 375×667, light and dark, AX5 text.

### OPH-467 — Ring screen contrast pairs in both themes and the DESIGN §11 grid rule

Kritik yol: push-notifications. W2 · dart-a · #46.

- [ ] New painted pairs of the ring screen into `scripts/design/contrast.py` for both themes (wash =
      surface + prioUrgent 10 %: onSurface, onSurfaceVariant, prioUrgent ≥ 4.5, outline ≥ 3, link),
      plus the Devices badge pair `onPrimaryContainer`/`primaryContainer` if missing; a failing pair
      is fixed in the widget with tokens only. The grid rule, short-screen and text-scale rules,
      pressed and failed states into DESIGN §11.
- **Acceptance:** every new pair passes in light and dark; `check:docs` green.
- **Test first:** `scripts/design/contrast.py` itself — the new pairs fail with a wrong value first.
- **Verify:** `python3 scripts/design/contrast.py && npm run check:fab && npm run check:opacity &&
  npm run check:typography && npm run check:docs` · `npm run verify:task --
  apps/app/test/notifications/alarm_ring_screen_test.dart` · `flutter analyze`.

### OPH-443 — Ring screen list mode, row snooze sheet, Tümünü ertele / Tümünü onayla

Kritik yol: push-notifications. W2 · dart-a · #47.

- [ ] Two or more ringing: list mode in place — header "{count} ACİL HATIRLATMA · 09:00", cards
      (title ≤ 2 lines, meta, 44 pills "Ertele ▾" and "Onayla", card tap = Aç), pinned "Tümünü
      ertele" grid (first three presets + "Saat seç…"), "Tümünü onayla ({count})".
- [ ] Row sheet: presets with their ring times, "Saat seç…", "Süresiz ertele", Tamamla, Aç; closing
      it leaves the row ringing. Rows leave in 220 ms (instant with reduced motion); the last row
      returns to the single layout (OPH-466). Confirmations "3 alarm 09:05’te tekrar çalacak", "3 alarm
      onaylandı"; announce on open.
- **Acceptance:** each path silences first; bulk actions stay pinned while the list scrolls.
- **Test first:** `test/notifications/alarm_ring_screen_test.dart` → 'snooze all emits one batch and
  silences once'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/alarm_ring_screen_test.dart
  apps/app/test/notifications/alarm_overlay_test.dart` · `python3 scripts/design/contrast.py && npm
  run check:fab && npm run check:opacity && npm run check:typography && npm run check:i18n` ·
  `flutter analyze`.
- **Device:** D-47a — three alarms at 09:00: one screen, one sound; "Tümünü ertele 5 dk" → one alert
  at 09:05; light and dark, 360×640.

### OPH-444 — Create, detail and quick add say when the minute already holds an urgent alarm

W2 · dart-a · #47.

- [ ] With urgent on and an alarm instant in a minute that holds another task's urgent alarm:
      `alarm.sharedMinute` ("09:00’da 2 acil alarm birlikte çalacak") + "Saati değiştir" (opens that
      instant's picker) under the urgent row of the create sheet and task detail; the quick-add
      "Eklendi" snackbar gets the line without a button.
- [ ] Never blocks, never shifts, no dialog; no other task's title is shown.
- I-12: no REST/MCP change — owner decision 2026-11-12 (info line only, no server rule).
- **Acceptance:** the Turkish line reads exactly as above; save always works.
- **Test first:** `test/features/tasks/urgent_minute_info_test.dart` → 'the create sheet shows the
  shared-minute line and still saves'.
- **Verify:** `npm run verify:task -- apps/app/test/features/tasks/urgent_minute_info_test.dart
  apps/app/test/features/tasks/create_sheet_header_test.dart
  apps/app/test/features/tasks/urgent_row_alignment_test.dart
  apps/app/test/features/tasks/quick_add_parse_flow_test.dart apps/app/test/notifications/urgent_minute_test.dart`
  · `npm run check:i18n` · `flutter analyze`.
- **Device:** D-47b — a second urgent task at 09:00 shows the line and saves; light and dark.

### OPH-445 — Android: a remote acknowledge or snooze cancels the notification ringing now

Kritik yol: push-notifications. W2 · dart-a · #48.

- [ ] `NotificationsGateway.activeNotifications()` (Android via `getActiveNotifications()`, else
      `[]`); pure `activeToCancel(active, alarms, now, staleWindow)` cancels a delivered urgent
      notification whose occurrence no longer rings (map through the scheduler's announced table if
      the plugin gives no payload). Runs every scheduler pass, the headless one included; the
      overlay closing because the alarm was handled elsewhere cancels its OS notification.
- **Acceptance:** on Android a ringing notification stops after the wake + sync; iOS, web and
  desktop unchanged.
- **Test first:** `test/notifications/active_alarm_reconcile_test.dart` → 'cancels the delivered
  urgent notification of a reminder acknowledged elsewhere'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/active_alarm_reconcile_test.dart
  apps/app/test/notifications/scheduler_test.dart apps/app/test/notifications/alarm_overlay_test.dart
  apps/app/test/notifications/gateway_local_settings_test.dart` · `npm run check:notify-matrix &&
  npm run check:push-payload` · `flutter analyze`.
- **Device:** B rings, acknowledge on A: B stops within the wake + sync time; again in Doze.

### OPH-446 — Device gate: `RingsUrgentHere` on/off/unknown/legacy, `DeviceApi` list/patch

Kritik yol: push-notifications. W2 · dart-b · #48.

- [ ] Pure `apps/app/lib/src/notifications/device_gate.dart`: `enum RingsUrgentHere`,
      `forThisDevice(alarms, here)` (off/unknown rebuild urgent inputs as normal).
- [ ] `ringsUrgentHereProvider` over localKv `alliswell_rings_urgent`; `DeviceRegistry.sync` caches
      the PUT answer (no field → `legacy`); a fresh sign-in or account switch → `unknown`; a restored
      session without a value → `legacy` (ADR-0069 #5). `DeviceApi.list()` and `patch(id,
      {ringsUrgent, deviceName})`. Applying the gate is OPH-452.
- **Acceptance:** a newly signed-in device never rings before the server said so; an updated
  install against an old server keeps ringing.
- **Test first:** `test/notifications/device_gate_test.dart` → 'unknown demotes, legacy keeps, off
  demotes, on keeps'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/device_gate_test.dart
  apps/app/test/features/devices/device_registry_test.dart apps/app/test/features/devices/push_key_lookup_test.dart
  apps/app/test/features/auth/account_switch_landing_test.dart` · `npm run check:notify-matrix &&
  npm run check:push-payload` · `flutter analyze`.

### OPH-447 — The app sends its device id on sign-in and refresh; a revoked family signs out and wipes

W2 · dart-b · #48.

- [ ] `AuthApi` register/login/oauth/refresh send `deviceId` = the sync client id when known — only
      once this server answered `ringsUrgent` (not `legacy`), or retried once without it on a 400.
- [ ] A refresh answered with a revoked or reused family ends in the same wipe as a sign-out and
      drops the OS alarms on the next start.
- **Acceptance:** sign-in and refresh never fail because of the field; a device removed elsewhere
  ends up signed out with its replica wiped.
- **Test first:** `test/features/auth/logout_wipe_test.dart` → 'a revoked family signs this device
  out and wipes local data'.
- **Verify:** `npm run verify:task -- apps/app/test/features/auth/auth_repository_test.dart
  apps/app/test/features/auth/logout_wipe_test.dart apps/app/test/features/auth/auth_interceptor_test.dart
  apps/app/test/features/auth/sign_out_server_switch_test.dart
  apps/app/test/features/devices/device_registry_test.dart` · `flutter analyze`.

### OPH-448 — Settings ▸ Devices: list, this-device badge, ring switch, states

W2 · dart-b · #48.

- [ ] `features/devices/devices_screen.dart` at `/settings/devices` + a "Cihazlar" row in the
      notification settings (subtitle names the ringing device or says none rings).
- [ ] Cards: platform badge, name, "Bu cihaz", "{platform} · {ago} görüldü", switch row (≥ 48)
      "Acil alarmları bu cihazda çaldır" (web: "bu sekmede" + "Yalnız sekme açıkken çalar"), off
      line, multi-device hint with the iPhone limit; sort this device, ringing, last seen; unseen >
      90 days folded. Optimistic switch, revert on failure; loading, error, offline, old-server and
      single-device states. Strings under `settings.devices.*`; do not edit `contrast.py` here.
- [ ] Pure `features/devices/device_display_name.dart`: the server stores the raw User-Agent as the
      name and the app sends none, so a null name or one starting `Dart/` or `Mozilla/` shows the
      platform label (iPhone, Android, Mac, Windows, Linux; web "{browser} · {OS}"); a user-set name
      is kept. Every place that names a device uses it. Test: 'a User-Agent name is shown as the
      platform label'.
- I-12: the switch, rename and remove go through REST only (OPH-433/435); MCP not extended.
- **Acceptance:** every device shows a readable name (never a raw User-Agent), platform, last seen;
  this device is marked; contrast passes in both themes.
- **Test first:** `test/features/devices/devices_screen_test.dart` → 'lists this device first with
  its badge, then the others by last seen'.
- **Verify:** `npm run verify:task -- apps/app/test/features/devices/devices_screen_test.dart
  apps/app/test/features/devices/device_registry_test.dart
  apps/app/test/features/devices/device_display_name_test.dart` · `python3 scripts/design/contrast.py
  && npm run check:fab && npm run check:opacity && npm run check:typography && npm run check:i18n` ·
  `flutter analyze`.
- **Device:** D-48b — iPhone, Android, web; light and dark; 2.0 text: switching on Android moves the
  alarm there.

### OPH-449 — Devices: rename, remove = sign out, last-device warning, pick page, new-device card

W2 · dart-b · #48.

- [ ] Detail sheet: name (≤ 40, empty → platform) + Kaydet (PATCH); Platform, Son görülme, Eklendi;
      "Cihazı kaldır" with "{device} kaldırılsın mı? O cihazda oturum kapanır." → DELETE (a
      `hasSession: false` device says the session could not be matched); this device: "Bu cihazda
      çıkış yap" → the existing sign-out.
- [ ] Switching off the last ringing device warns and allows it; a removal that leaves none opens
      "Acil alarmlar hangi cihazda çalsın?" preselected to the promoted device. `NewDeviceAlarmCard`
      (once per account + device): "Bu cihazda acil alarmlar kapalı. Alarmlar {device} çalıyor." with
      the locative helper, "Bu cihazda da çal" / "Tamam" (placed by OPH-453).
- **Acceptance:** remove = sign out of that device; urgent alarms are never lost silently.
- **Test first:** `test/features/devices/devices_screen_test.dart` → 'removing the ringing device
  opens the pick page with the promoted device selected'.
- **Verify:** `npm run verify:task -- apps/app/test/features/devices/devices_screen_test.dart
  apps/app/test/features/devices/new_device_alarm_card_test.dart` · `python3 scripts/design/contrast.py
  && npm run check:fab && npm run check:opacity && npm run check:i18n` · `flutter analyze`.
- **Device:** D-48d — remove the ringing iPhone from Android: the pick page preselects Android; the
  iPhone signs out at its next refresh.

### OPH-450 — Native group snooze: one event, group title, +1 minute from the ledger

W2 · swift · #47.

- [ ] Group schedule args (several members, "3 acil alarm") render unchanged and survive a native
      snooze; snooze and stop of a group enqueue one event with every member.
- [ ] `AWSnoozeTarget.compute(pressedAt:preset:ledger:snoozedAlarmId:calendar:)` adds the §2b.3
      +1 min rule (ledger only, ≤ 30 tries). No Dart counterpart (ADR-0068 #6).
- **Acceptance:** a native group snooze leaves one alarm for all members, never in a minute the
  ledger already holds.
- **Test first:** `ios/RunnerTests/SnoozeTargetTests.swift` → `testTakenMinuteShiftsOneMinute`.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator --debug`.
- **Device:** D6 variant — three at 09:00 and another at 09:05; native Ertele (5 dk) with the app
  killed rings all three once at 09:06.

### OPH-451 — Widget timeline: each entry renders its own day; stale state past the horizon

W2 · swift · #50.

- [ ] First move `AWSnapshot` and its nested Codable structs out of `AllisWellWidget.swift` (widget
      target only) into `ios/Shared/AWSnapshotModel.swift` + an optional `days`; add it to Runner and
      the widget by `wire_alarmkit.rb` and to the macOS widget's shared list
      (`macos/scripts/add_widget_extension.rb`). Otherwise nothing in Runner can take `AWSnapshot`.
- [ ] Pure `awDayView(for:in:calendar:)` in a new `ios/Shared/AWWidgetDayPick.swift` (`.day`,
      `.stale`, `.topLevel` for v5), wired into the widget and Runner targets by script.
- [ ] `awTimeline`: header, counter, lock-screen next and the project view come from the entry's day;
      past the horizon the list becomes `strings.stale`, counter and next hidden; the archive budget
      counts one day. Tolerant Codable decoding (new fields optional); no network, no BGAppRefresh.
- **Acceptance:** after midnight the new day's Today shows without Dart; never yesterday's list
  under today's date.
- **Test first:** `ios/RunnerTests/WidgetDayPickTests.swift` → `testEntryPicksItsOwnDay`.
- **Verify:** Mac — `ruby -c` on both scripts and a second `wire_alarmkit.rb` run that changes
  nothing, `xcodebuild test -only-testing:RunnerTests`, `flutter build ios --simulator --debug`
  (+ `flutter build macos` when the Mac can build it, else NOT RUN).
- **Device:** D10 — 23:58 → 00:02 without opening the app; three days later the stale line.

### OPH-452 — Apply the device gate in the foreground scheduler, the overlay and the headless turn

Kritik yol: push-notifications. W3 · wire · #48.

- [ ] `notificationSchedulerProvider` watches `ringsUrgentHereProvider` and plans
      `forThisDevice(...)`; a change re-plans at once. The overlay's feed applies the same gate.
      `runHeadlessRefresh` reads the flag from localKv before `applyOnce` (unknown → normal,
      legacy → urgent); the Android active-notification reconcile runs there too. Nothing iOS-headless.
- **Acceptance:** urgent alarms ring only where the flag is on or legacy; every other device gets a
  normal notification; switching on re-plans without a restart.
- **Test first:** `test/notifications/headless_parity_test.dart` → 'headless applies the same device
  gate as the foreground'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/headless_parity_test.dart
  apps/app/test/notifications/alarm_overlay_test.dart apps/app/test/notifications/device_gate_test.dart
  apps/app/test/notifications/scheduler_test.dart` · `npm run check:notify-matrix && npm run
  check:push-payload` · `flutter analyze`.
- **Device:** D-48a end to end — iPhone on, Android off: at 09:00 only the iPhone rings.

### OPH-453 — New-device card on Home; "no ringing device" item in the alarm band

Kritik yol: push-notifications. W3 · wire · #48.

- [ ] `NewDeviceAlarmCard` at the top of Home's Today when this device is off, another rings and
      the card was not dismissed.
- [ ] Alarm band item "Acil alarm çalan cihaz yok" + "Cihaz seç" → `/settings/devices` when no
      device rings. Both read the cached device list; offline adds nothing.
- **Acceptance:** the card shows once per account and device, never on the ringing one; the band
  item goes as soon as a device rings.
- **Test first:** `test/notifications/alarm_banner_test.dart` → 'the band says no device rings
  urgent alarms and links to Devices'.
- **Verify:** `npm run verify:task -- apps/app/test/features/devices/new_device_alarm_card_test.dart
  apps/app/test/notifications/alarm_banner_test.dart apps/app/test/features/home` · `python3
  scripts/design/contrast.py && npm run check:i18n && npm run check:home` · `flutter analyze`.
- **Device:** D-48e — after the update a non-ringing phone shows the card once.

### OPH-454 — Cross-lane tests: native snooze → batch → plan converges; group + device gate

Kritik yol: push-notifications. W3 · wire · #47.

- [ ] Against fakes (AlarmKit host with a ledger, in-memory database): a native group snooze pulled
      → one receipt → plan → one alarm at 09:05 with three members, ack after commit, redelivery a
      no-op; the same minute with the gate off → normal notifications, no ring screen; a remote
      acknowledge while the group alerts → `stop`, not `cancel`. A seam bug found here is fixed in
      its owning file with its own regression test.
- **Acceptance:** the end-to-end paths are green without a device.
- **Test first:** `test/notifications/cross_lane_alarm_test.dart` → 'a native group snooze converges
  to one AlarmKit alarm after the pull, the batch and the plan'.
- **Verify:** `npm run verify:task -- apps/app/test/notifications/cross_lane_alarm_test.dart
  apps/app/test/notifications` · `flutter analyze`.

### OPH-455 — Regenerate artefacts and run the gates

Kritik yol: push-notifications. W3 · wire · #48.

- [ ] `platform_matrix.dart` rows for what moved (Android task/project wake and remote stop; iOS
      grouped AlarmKit alarm and native snooze; the device gate everywhere) → `npm run
      check:notify-matrix -- --write`; `npm run api:docs`; sync fields expected unchanged. Generation
      only (no test first unless a matrix row changes).
- **Acceptance:** every `check:*` gate green with no uncommitted generated diff.
- **Verify:** `npm run check:notify-matrix && npm run check:sync-fields && npm run check:openapi &&
  npm run check:apidocs && npm run check:postman && npm run check:i18n && npm run check:push-payload
  && npm run check:no-ee && npm run check:no-ts` · `npm run verify:task --
  apps/app/test/notifications/platform_matrix_test.dart`.

### OPH-456 — PR-1 docs at group end

W3 · wire · #46–#50.

- [ ] Written before the code and checked here against what shipped (amend by appended note, never
      by editing an accepted decision): ADR-0068, ADR-0069 (its #6 is the session binding — a
      separate ADR only if the auth work changed it), the ADR-0015 and ADR-0010 revisions,
      NOTIFICATIONS §2b.3, STATE "Sahip kararları".
- [ ] `docs/WIDGETS.md` snapshot v6 + stale; root `CHANGELOG.md` `[Unreleased]` lines for #46–#50 (#50: the
      swiped-away case comes with the next update); DEVICE-CHECKS one NOT RUN row per device check
      above; STATE Snapshot and "Kullanıcıdan bekleyen": confirm the 14-day backfill guard; LESSONS:
      `.custom` needs `stop` in `perform()`, never `cancel` an alerting alarm.
- [ ] Candidate tasks into TASKS: iOS NSE + `AlarmManager.stop` spike, iOS BGAppRefresh + silent
      push, WidgetKit push (.p8), Android headless refresh race, macOS widget self-fetch, excluding
      the acknowledging client from the alarm-stop wake. Then delete the blocks of OPH-421…456,
      OPH-466 and OPH-467 (closed); OPH-457…465 stay for PR-2.
- **Verify:** `npm run check:docs && npm run check:no-ee`. Documentation only.

---

## Epic 37 — Widget fetches its own data (#50, PR-2)

The swiped-away half of #50: with the app force-quit, iOS runs neither background refresh nor a
silent push, so the widget extension fetches its own view with a read-only widget token. Starts
after Epic 36 merges. Owner decisions 2026-11-12: self-fetch is in scope; iOS background sync,
WidgetKit push and macOS self-fetch are not. Acceptance is softened (S-50): a change made elsewhere
appears within one WidgetKit reload (typically 15–60 min), with no minute guarantee. The grouping
fixture is born in OPH-463 and must reach the API lane before OPH-459. The self-fetch contract
(Keychain item, App Group keys, `/widget/snapshot` schema) is written in OPH-457 before any lane
starts; where a task and the contract differ, the contract wins. Swift tests run on the Mac as in
Epic 36.

### OPH-457 — ADRs and contract first: widget token, shared Keychain group, self-fetch contract

W4 · api · #50.

- [ ] ADR "Widget identity: a non-rotating, read-only widget token" — `aww_` prefix, shown once,
      HMAC hash (ADR-0032 pattern), scope `GET /widget/snapshot` only, one per device, 90 days
      renewed in the foreground under 30, no refresh; revoked with the device, sign-out, password
      change and a dead minting family; MCP not extended; JS grouping locked to the shared fixture
      (DESIGN §8 W9 revision: Dart defines the rule, the server is a second implementation).
- [ ] ADR "Shared Keychain group, AfterFirstUnlock" — the widget token only, access group
      `group.com.alliswell.alliswell`, `AfterFirstUnlockThisDeviceOnly` (assumption recorded);
      session tokens stay app-private and `WhenUnlocked`. Index rows; revision notes on ADR-0038 §8
      and ADR-0010 §5; `.claude/rules/auth.md` names the new widget paths and test (≤ 60 lines).
- [ ] `docs/WIDGETS.md` "Widget self-fetch contract": the Keychain item (`kSecAttrService`,
      `kSecAttrAccount` as flutter_secure_storage lays out key `aw_widget_token` in the version
      pinned in `pubspec.lock`, access group, accessibility), every App Group key the widget reads
      or writes with its JSON type (fetch profile, `aw_widget_token_state`,
      `aw_widget_server_snapshot`, success and backoff stamps), and the `/widget/snapshot` request
      and response schema. OPH-460, OPH-462, OPH-463 and OPH-464 implement it.
- **Acceptance:** both ADRs and the contract exist before any W4 code commit.
- **Verify:** `npm run check:docs && npm run check:no-ee`. Documentation only.

### OPH-458 — Widget tokens: table, mint route, `authenticateWidget`, revocation

Kritik yol: auth. Kritik yol: migrations. W4 · api · #50.

- [ ] `apps/api/migrations/20261112140000_create_widget_tokens.js` (later timestamp if main moved):
      user (FK cascade), device (unique per user), session family, token hash, created/expires/
      last used/revoked.
- [ ] `POST /widget-tokens {deviceId}` (session only, API keys rejected; upsert revokes the previous
      one; returns `aww_…` once); `hashWidgetToken` (separator `widget:`); `app.authenticateWidget`
      accepts only `aww_` with a live device and family; `app.authenticate` unchanged. Revoked by
      device delete, logout, logout-all, session revoke, password change, reuse. `npm run api:docs`.
- I-12: REST yes; MCP no — device infrastructure.
- **Acceptance:** a leaked widget token reads only the widget view and dies with the device or the
  session; no existing auth path changes.
- **Test first:** `apps/api/test/integration/widget-tokens.test.js` → 'a widget token reads only the
  snapshot and is refused everywhere else'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/widget-tokens.test.js
  apps/api/test/integration/auth.test.js apps/api/test/integration/auth-refresh.test.js
  apps/api/test/integration/auth-me.test.js apps/api/test/integration/sessions.test.js
  apps/api/test/integration/mfa.test.js apps/api/test/integration/notification-devices-signout.test.js`
  · `npm run check:openapi && npm run check:apidocs && npm run check:postman && npm run check:no-ee`.
- **Device:** D-W9 — sign out or remove the phone: the widget gets 401 at its next reload and stops.

### OPH-459 — Server widget grouping in JS locked to the shared fixture

W4 · api · #50.

- [ ] `apps/api/src/lib/widget-grouping.js` ports the widget grouping (buckets, +7/+30, events,
      overdue and plan day per ADR-0053, open today, next, 12 rows + more, project views, time
      style) language-free; day boundaries from the client tz. Needs OPH-463's fixture in main first.
- **Acceptance:** every fixture case passes in Vitest and in `flutter test`.
- **Test first:** `apps/api/test/unit/widget-grouping.test.js` → 'server grouping matches the shared
  fixture'.
- **Verify:** `npm run verify:task -- apps/api/test/unit/widget-grouping.test.js
  apps/app/test/features/widgets/widget_core_test.dart`.

### OPH-460 — `GET /widget/snapshot`: v6 day views for the widget token

Kritik yol: auth. W4 · api · #50.

- [ ] `GET /widget/snapshot?tz=&locale=&days=3&list=&private=` (widget token only): days 0..2 in the
      v6 shape + `generatedAt`; `private=1` omits every title and summary; scope = the device's list
      with membership enforced; events only for one workspace; invalid tz 400; ETag/304; `no-store`.
      No labels from the server; the body is the WIDGETS.md self-fetch contract's. `npm run api:docs`.
- I-12: REST yes; MCP no — device infrastructure.
- **Acceptance:** the body matches the Dart v6 day view for the same data; only the widget token
  opens it.
- **Test first:** `apps/api/test/integration/widget-snapshot.test.js` → 'private=1 returns no title
  or summary field anywhere in the body'.
- **Verify:** `npm run verify:task -- apps/api/test/integration/widget-snapshot.test.js
  apps/api/test/integration/widget-tokens.test.js apps/api/test/integration/auth.test.js
  apps/api/test/integration/auth-refresh.test.js apps/api/test/integration/auth-me.test.js
  apps/api/test/integration/sessions.test.js apps/api/test/integration/mfa.test.js` · `npm run
  check:openapi && npm run check:apidocs && npm run check:postman && npm run check:no-ee`.
- **Device:** D-W3 — private widget on: no titles in the response.

### OPH-461 — Pure snapshot choice and fetch backoff

W4 · swift · #50.

- [ ] `ios/Shared/AWWidgetFetchPolicy.swift`: `awPickSnapshot` (queued widget completions overlay
      the server view; local wins when newer or a completion is pending), `awShouldFetch` (no
      profile or unreadable private flag → never; < 2 min since success → no; inside backoff → no),
      `awNextBackoff(n)` = min(5 min · 2ⁿ, 2 h), `awReloadDate` (≤ now + 30 min + jitter; midnight
      00:01 + 0–5 min).
- **Acceptance:** self-fetch never undoes a change made on the phone that has not synced yet.
- **Test first:** `ios/RunnerTests/WidgetFetchPolicyTests.swift` → `testPendingWidgetCompletionKeepsTheRowDone`.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator --debug`.

### OPH-462 — Widget extension fetches `GET /widget/snapshot` with an 8 s timeout

W4 · swift · #50.

- [ ] In the timeline providers: local snapshot first; if `awShouldFetch`, read the token from the
      shared Keychain group (names exactly as the WIDGETS.md self-fetch contract states), one
      ephemeral request (6 s request / 8 s resource, no waiting for connectivity). 200 → App Group
      `aw_widget_server_snapshot` (never Dart's key) → pick → day view; 304 → success stamp; 401 →
      `aw_widget_token_state = invalid`, stop until the app re-mints; failure → backoff, local
      snapshot. Strings come from Dart's profile. No WidgetKit push, no BGAppRefresh, macOS untouched.
- [ ] The fetcher lives in `ios/Shared/AWWidgetFetcher.swift` (Runner + widget by script, so
      RunnerTests can test it with an injected `URLProtocol`); the call site is `#if os(iOS)`.
- **Acceptance:** swiped away, a change elsewhere shows within one WidgetKit reload; offline renders
  the last snapshot within 8 s.
- **Test first:** `ios/RunnerTests/WidgetFetchPolicyTests.swift` → `testUnauthorizedMarksTheTokenInvalidAndStops`.
- **Verify:** Mac — `xcodebuild test -only-testing:RunnerTests` and `flutter build ios --simulator --debug`.
- **Device:** D8/D-W1 (Developer Mode off, app swiped away: minutes until a Mac change shows), D-W2
  (after first unlock fetches; before it does not), D-W4 (midnight closed).

### OPH-463 — Shared widget grouping fixture and the App Group fetch profile

W4 · dart-c · #50.

- [ ] `apps/app/test/fixtures/widget_grouping_cases.json` (now, tz, tasks, events, scope, private →
      v6 day views in the language-free shape; day boundaries, overdue, +7/+30, events by scope,
      private, 12-row cap), written with `UPDATE_FIXTURES=1`. Cherry-picked to main before OPH-459.
- [ ] App Group profile {baseUrl, scope, private flag — written only after "Private widget" was read,
      strings incl. bucket labels and stale, date/time patterns, pendingOutbox, localWrittenAt} —
      keys and types as the WIDGETS.md self-fetch contract states. No token here.
- **Acceptance:** one fixture for both runtimes; no profile → the extension never fetches.
- **Test first:** `test/features/widgets/widget_fetch_profile_test.dart` → 'profile is written only
  after Private widget has been read'.
- **Verify:** `npm run verify:task -- apps/app/test/features/widgets/widget_core_test.dart
  apps/app/test/features/widgets/widget_fetch_profile_test.dart
  apps/app/test/features/widgets/widget_private_test.dart` · `flutter analyze`.

### OPH-464 — `WidgetTokenStore`: mint on sign-in, renew in the foreground, delete on sign-out

W4 · dart-c · #50.

- [ ] `features/widgets/widget_token_store.dart`: a separate secure store in the App Group access
      group, first-unlock-this-device; session storage unchanged. iOS only: mint after the device
      registered, renew on resume under 30 of 90 days, on sign-out delete the server record then
      the local item, re-mint after an extension 401; an old server (404) → no token until restart.
      Never log the token. Service, account and access group as the WIDGETS.md contract states.
- **Acceptance:** the extension reads the token after first unlock; other platforms do nothing new.
- **Test first:** `test/features/widgets/widget_token_store_test.dart` → 'widget token uses the app
  group and first_unlock_this_device'.
- **Verify:** `npm run verify:task -- apps/app/test/features/widgets/widget_token_store_test.dart
  apps/app/test/features/widgets/widget_token_lifecycle_test.dart
  apps/app/test/features/auth/logout_wipe_test.dart` · `flutter analyze`.
- **Device:** D-W2 — the extension reads the item the app wrote (access group and service name).

### OPH-465 — PR-2 close: notify matrix, API reference, CHANGELOG, DEVICE-CHECKS, STATE

Kritik yol: push-notifications. W4 · wire · #50.

- [ ] iOS matrix row "widget: self-fetch with a read-only widget token" → `npm run
      check:notify-matrix -- --write`; check (not regenerate) the API reference; the `docs/WIDGETS.md`
      self-fetch contract checked against what shipped; root `CHANGELOG.md` `[Unreleased]` #50 line
      (no minute guarantee); DEVICE-CHECKS D8, D-W1…D-W5, D-W8, D-W9; STATE: S-50 owner-pending if
      not confirmed; candidates WidgetKit push and macOS self-fetch; delete the OPH-457…465 blocks.
- **Verify:** `npm run check:notify-matrix && npm run check:openapi && npm run check:apidocs && npm
  run check:postman && npm run check:docs && npm run check:no-ee && npm run check:push-payload`.

---

## Sahibin adımını bekleyen işler — ajan için kod işi yok

Kod tarafları kapalı; kalan kutular sahibin hesap/panel adımları (STATE → "Kullanıcıdan bekleyen").

### OPH-142 — Critical-alerts entitlement application (user action; code is ready) ⏸️ SAHİP

_(2026-07-24'te başvuru "gönderiliyor" diye kayıtlı; sonucu kayıtlı değil — gönderildiyse ilk
kutuyu işaretle.)_

- [ ] **Mahir (Account Holder):** submit
      <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/> —
      justification draft in NOTIFICATIONS.md §2. Expect refusal for a task manager; AlarmKit
      (OPH-141) is the primary path — this is belt-and-braces for muted phones on iOS < 26.
- [ ] If granted: add `com.apple.developer.usernotifications.critical-alerts` = true to
      `Runner.entitlements`, regenerate provisioning profiles. **No code change** — OPH-139
      already gates on the runtime grant, and the second "Critical Alerts" permission prompt +
      Settings toggle appear automatically.

---

## Backlog / v2 parking lot

Yapılmamış ve bir işe bağlanmamış her şey. Bir madde bir epic'e alınınca buradan silinir.

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Timeline view; smart lists/filters DSL (kanban shipped in Epic 15 — OPH-168).
- Search v2: FTS5 external-content upgrade (bm25 ranking — ADR-0013 upgrade path),
  server-side fold columns for a first-class API `?q=` (the server's FULLTEXT still folds `I`
  but not `ı` — OPH-167), file-name search inside Dosyalar (OPH-170; the global palette
  already finds files by name — OPH-374).
- Task description v2: OG link previews (needs a server-side unfurl proxy — OPH-164, OPH-201),
  rich formatting.
- Tag management v2: merge tags, usage counts, tag colors in board/list filters.
- Files v2: desktop drag-to-move into folders (target-picker sheet is v1), bulk move/delete.
- Attachments v2: multipart >5 GB uploads, thumbnails/transcodes, storage quota in the plain
  build (today only the per-file `maxUploadBytes` ceiling), local binary cache for offline
  viewing, inline video playback, public share links (v1 shipped in Epic 14 — ATTACHMENTS.md §11).
- **Round 9 park kuyruğu:** sunucu tarafı zil sesi dönüştürme (ffmpeg → ≤30 sn caf, mp3
  yüklemelerini iOS bildiriminde kullanılabilir kılar — OPH-181 bilinçli olarak
  doğrulama+dürüst mesajla yetiniyor); **watchOS companion hedefi** (özel long-look +
  `WKInterfaceDevice` haptikleri + complication — kararı OPH-183 veriyor); cihazlar arası
  **sunucu tarafı ayar deposu** (hatırlatıcı profili + tarih biçimi + ses seçimi bugün
  cihaz-yerel, `notification_privacy` kalıbıyla aynı); alarm günlüğünün sunucuya raporlanması.
- **Round 10 park kuyruğu (kararı OPH-195 verir):** alt görevler (`parent_task_id` —
  şema, API ve kaskadlı silme hazır, arayüz yok), görev rengi (`tasks.color_rgb` — widget
  kullanıyor, kullanıcı seçemiyor), **elle sıralama** (`sort_order` sıralamada kullanılıyor ama
  sürükleme yok), gerçek süre (`actual_minutes`),
  proje ikonu/başlangıç-bitiş tarihi; Tamamlananlar ekranında arama + `cancelled`/`archived`
  sekmesi; Pano kartlarında kaydırarak silme (yatay pager jest çakışması); sunucu tarafı
  "tamamlananlar" ucu (bugün tamamen yerel replikadan okunuyor); geri alma olmayan silmeler
  (dosya, checklist öğesi, hatırlatıcı adımı).
- **Round 11 park kuyruğu — Hızlı Erişim (OPH-196'da kesinleşti, 2026-07-29):** Android
  sistem-geneli overlay düğmesi (SYSTEM_ALERT_WINDOW — ayrı izin ve istila, kendi turu;
  Messenger bile chat head'i Android 11'de Bubbles API'sine taşıdı, yani "uygulama dışı
  yüzen düğme" artık OS'un kendi kanalı üzerinden yapılan bir iştir); iOS'ta uygulama dışı
  yüzen düğme (OS üçüncü partiye izin vermez — yazılı sınır); kısayol klasörleri / iç içe
  liste (tek 50'lik liste için ikinci hiyerarşi seviyesi; Slack'in kendi önerisi de "3–5
  bölüm"); dış linklerde OG başlık çekme (unfurl proxy'ye bağlı); workspace-paylaşımlı ekip
  kısayol listesi (ADR-0018 "shared team list" alternatifi — additive, v2); emoji-picker
  paketi (tam ızgara — ADR gerektirir, gerekçesi yok); **kısayol renginde sınırsız palet**
  (`_ColorGridDialog`'un tüm `Colors.primaries` seti — DESIGN §23 Q8a: sınırsız fille
  kontrast garanti edilemiyor, kısayolda yalnız 10'luk palet sunuluyor); **yüzen düğme
  opaklık slider'ı** (AssistiveTouch'ta var; bizde tek anahtar + %40 sabiti yeterli sayıldı);
  kısayol satırından hedefi yeniden adlandırma (kısayol adı hedefin adı değildir — §4.12).
- **Round 11 park kuyruğu — AI (gerekçeler [AI.md](AI.md) + ADR-0019/0022/0023):**
  abonelik-OAuth entegrasyonu (üç sağlayıcıda da kapalı/bekleme listesi — üç ayda bir
  yeniden bakılır; `auth_mode='oauth_subscription'` rezerve); sohbette yazma araçları
  v1.5 (`complete_task`/`reschedule_task` onay-kapılı; **silme kalıcı olarak hariç**);
  yüksek-güvende onay kartını atlama anahtarı (v1.5 opt-in); senkron sohbet geçmişi
  (`conversation` varlığı — gizlilik duruşu değişikliği, bilinçli karar ister);
  sunucu-STT varsayılanı (OpenAI/Gemini ses — v1.5 ayarı); gerçek-zamanlı sesli sohbet
  (speech-to-speech); doğal-dil filtreleri → akıllı liste DSL'i (önce DSL); akıllı
  zamanlama (takvim boş/dolu akıl yürütmesi); otomatik etiket/öncelik önerisi;
  haftalık AI özet e-postası; barındırılan ücretli "AllisWell AI" katmanı (ürün kararı);
  paylaşımda dosya/görsel anlama; günlük/haftalık AI incelemesi + not özetleme +
  toplantı-notu→görevler (v1.5 adayları — Epic 19 çıkarım ucunu yeniden kullanır).
- **Round 17 park kuyruğu — Markdown (gerekçeler [MARKDOWN.md](MARKDOWN.md) §3):**
  `[[wikilink]]`'ler + geri bağlantılar (bir bağlantı indeksi ister — kendi başına bir
  özellik); graf görünümü, PDF üzerine not alma, atıf/BibTeX (**reddedildi** — başka bir
  ürün); yazma hedefleri (Ulysses); editör içi AI ("devam ettir", "yeniden yaz" — Epic 20'nin
  altyapısı hazır, ürün kararı); ePub dışa aktarma (DOCX kapandı — ADR-0048); klasör/vault izleme (**reddedildi** —
  biz markdown'ı iyi okuyan bir görev uygulamasıyız, Obsidian değiliz); Vim/Emacs kısayolları
  ve özel CSS temaları (**reddedildi** — Rule 11, tek tasarım sistemi); göreli yollu görseller
  (`./x.png` bugün sebepli yer tutucuyla çiziliyor — OPH-247); bölünmüş görünümde satır eşlemeli
  senkron kaydırma (bugün oransal — `markdown_forge` reposunda `lib/src/edit/source_mode.dart`, OPH-248);
  dış dosyanın diskte değişmesini canlı izleme (bugün yalnız kaydetmede çatışma + elle
  `reprobe` — OPH-251).
- **Round 18 park kuyruğu (gerekçeler ADR-0031/0032):** **generic OIDC girişi**
  ([issue #2](https://github.com/mahirozdin/alliswell/issues/2) — Authentik/Keycloak/
  PocketID; meşru ve Firebase-sosyal-girişten farklı: sunucu yarısı ucuz çünkü ADR-0026'nın
  `src/lib/oauth-identity.js`'i zaten JWKS+issuer+audience doğrulaması ve subject-öncelikli
  hesap merdiveni taşıyor — iş "güvenilen issuer listesi + OIDC discovery'yi konfigürasyona
  açmak"; pahalı olan istemci yarısı: 6 Flutter platformunda authorization-code+PKCE tarayıcı
  akışı, deep-link dönüşü, ayar/doc yüzeyi. Tetikleyici: çok kullanıcılı workspace UI'ı
  açıldığında ya da talep birikince kendi epic'i olur); markdown'a renk sözdizimi (GFM'de yok
  — `==mark==` vurgusu var, gerisi Live/Delta tarafında; DESIGN §33 R6); Home/Projeler liste
  sıralaması (DESIGN §34 L5 yazılı sebepleri); notlar zip/dosya-başına toplu export (v1 JSON —
  OPH-266); API anahtarlarına scope'lar (v1 bilinçli scope'suz — ADR-0032 revizyonu ister);
  sürüm geçmişinde adlandırılmış/sabitlenmiş sürümler (Google Docs deseni; saklama
  inceltmesinden muafiyet mekanizması hazır, UI ürün kararı bekler); not etiketlerinin not
  push protokolüne girmesi (v1 bilinçli sınır: etiket yalnız REST `PUT /notes/:id/tags` ile
  yazılır, pull okur — OPH-261).
- ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), F-Droid/TestFlight packaging.
- **İstemci yüklemelerinin taranması** (2026-09-24 incelemesi) — sunucunun kendi aldığı
  dosyalar bir uzantıda taranabiliyor; istemcinin presigned yüklemesi kovaya doğrudan gider
  ve taranmaz. Doğru çözüm kovada asenkron tarama + indirme kapısıdır (`files` satırında
  durum) — kendi turu.
- **CalDAV VTODO görev senkronu** — tasarım [CALDAV.md §9](CALDAV.md); seçenek: bağlayıcının
  VTODO'su ya da AllisWell'in kendisinin CalDAV sunucusu olması (sahip kararı).
- **İçe aktarma önizlemesinin `googleMirror` uyarısı CalDAV hesaplarını saymıyor** (OPH-380) —
  büyük bir içe aktarma bağlı iCloud/Nextcloud takvimini sessizce doldurur.
- **Google bağlantısı kesilince önbellekteki kendi etkinlikleri canlı kalıyor** (OPH-082 takibi,
  2026-10-17 ölçüldü) — `DELETE /integrations/google/accounts/{id}` hesabı soft-delete ediyor,
  `calendar_external_events` satırlarına dokunmuyor (FK CASCADE yalnız sert silmede); takvim
  görünümünde kesilmiş hesabın toplantıları kalıyor. CalDAV'ınki düzeltildi (OPH-380): aynı
  transaction'da `recordSyncWrites` ile mezar taşı.

### Ölçülmüş açıklar ve bilinen sınırlar (2026-09-26 temizliğinde toplandı — hiçbiri bir işe bağlı değildi)

- **Bozulmuş takvim serilerinin onarımı (sahip kararı bekliyor, 2026-10-17)** — `44a9e2e` öncesi her seri düzenlemesi geleceği silip tarihlerini tutuyordu (OPH-205'ten beri, v0.8.0–v1.17.0); bu satırlar kendiliğinden geri gelmez. Önce prod'da etkilenen seri sayısını ölç; onarım = sistemin sildiği satırların tarihini bırakan tek seferlik migration (kullanıcı silmelerinden ayırmak şart).
- **Görev tarihlerinde 100'den küçük yıllar ve aralık denetimi** (QA 2026-10-17 ölçtü, eski) — `PATCH /tasks/{id}` `startAt: 0001-01-01T00:00:00Z` → yanıt `2001-01-01` (mysql2 iki haneli yılı 19xx/20xx okuyor, `db/knexconfig.js` bağlantısı); `9999-…` sınırsız kabul (`routes/tasks.js` yalnız `format: date-time`).
- **Web teslimatı Kapalı iken alarm bandı** — Kapalı düşürülen aboneliği `webPushOff` diye
  raporluyor: bant dırdır ediyor ve "Tekrar kontrol et" kullanıcının Kapalı seçimine rağmen
  yeniden abone ediyor (`gateway_web.alarmSupport`, OPH-316'nın modu okunmuyor). 2026-09-26'da
  #19 turunda ölçüldü.
- **OPH-337** — `LocalKv` okunamazsa "Gizli widget" (ve bildirim gizliliği) hata vermeden
  "hiç ayarlanmamış" okunur → başlıklar widget'a yazılabilir.
- **OPH-226** — AI bağlantısının `baseUrl`'i korumasız bir SSRF yüzeyi (bilinçli kabul; yalnız
  SECURITY.md "AI ayarlarını güvenilen kullanıcılara açın" diyor).
- **ADR-0038 §8** — iOS başsız uyanış ertelendi: kilitli iPhone Keychain'i okuyamıyor
  (`WhenUnlocked`); erişilebilirlik değişikliği kendi güvenlik ADR'sini + yeniden anahtarlama
  göçünü ister.
- **OPH-366 (ölçüldü)** — Flutter web'de Google düğmesi `google_sign_in` `authenticate()`
  çağırıyor; `google_sign_in_web` bunu desteklemiyor (`renderButton`/GIS gerekir) → web'de
  Google ile giriş bugün çalışmıyor.
- **OPH-025** — web'de httpOnly refresh-cookie sertleştirmesi (web oturumu bugün localStorage'da,
  `LocalKvSecretStore`).
- **OPH-324 takibi** — release APK'nın `res/raw` seslerini gerçekten taşıdığını ölçen artefakt
  kapısı hiç yazılmadı (`scripts/android/assert-permissions.sh` kalıbı).
- **OPH-236 (ikon)** — `scripts/design/branding_icons.py --check` hiçbir CI iş akışına bağlı değil.
- **OPH-193** — `check:i18n` yalnız literal kalıpları tarar; `Text(değişken)` ile basılan ham
  enum'u (`Text(project.status)`) göremez — kural ya da lint yok.
- **OPH-318** — uygulama dili değişince Android bildirim kanalının adı eski dilde kalıyor (önce
  ölç: aynı id'yle `createNotificationChannel` adı güncelleyebilir).
- **OPH-336** — widget yapılandırma sayfasının kendi etiketleri ("List", açıklama) İngilizce;
  native metaveri uygulamanın çevirisine ulaşmıyor.
- **OPH-181** — Android'de yüklenen özel ses bildirim kanalının sesi olamaz (FileProvider gerekir;
  bugün yalnız uygulama içi alarmda çalar); AlarmKit'in container'daki (`Library/Sounds`) sesi erken
  iOS 26'da çalmama raporu ölçülmedi — "çalmazsa paketli sese düş" yolu yok.
- **OPH-126** — oturum açılışında uygulama dilini `users.locale`'den tohumlama.
- **OPH-110** — kaskadlı arşivden çıkarma projenin TÜM arşivli öğelerini geri getirir (v1
  sadeleştirmesi; kaskadın dokunduklarını izlemek yeni kolon ister).
- **OPH-261** — proje arşiv kaskadı domain katmanında değil (`routes/projects.js`); MCP'de proje
  arşivleme bu yüzden yok.
- **OPH-168** — Pano: "2/5" konum etiketi ve dikey kenar otomatik kaydırması v1'den kırpıldı.
- **OPH-081** — drift'in üretilmiş şema-test aracına dönüş (drift_dev ↔ drift sürümleri
  hizalanınca); bugün göç testleri elle.
- **OPH-245** — `imageCache` bayt ölçümü hiç alınmadı (büyük fotoğraflarda bellek davranışı varsayım).
- **OPH-256** — macOS Release dağıtım imzası (Developer ID + noterleme) kararı verilmedi.
- **OPH-227** — README/mağaza için AI bubble ve onay kartı ekran görüntüleri yok.
- **`docs/SELF-HOSTING.md` §4** — yükseltme öncesi yedek komutunda `--no-tablespaces` eksik
  (§4b'dekinde var); PROCESS yetkisiz kullanıcıda korkutucu ama zararsız bir "Error:" basar.
