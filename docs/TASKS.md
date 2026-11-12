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

## Epic 36 follow-up — phase-end review findings (PR-1)

Left open by the Epic 36 phase-end review (2026-11-12) and still present in the code; they fix
shipped PR-1 behaviour, so they come before Epic 37. Each: failing test first, K1, commit body with
`Changelog:` and `Device:` lines.

### OPH-468 — A revoked session's cleanup finishes before any replacement session is exposed

Kritik yol: auth. Found: phase-end review, `apps/app/lib/src/features/auth/data/auth_repository.dart`
(`_doRefresh` deferred branch, `_setSession`).

- [ ] Deferred branch: the old session's `_clearSession` (storage delete) is not awaited by the
      sign-in that takes the cleanup over → a slow delete finishes after B saved and erases B,
      publishing null (reproduced: stored=null, events `[A,B,null]`).
- [ ] Overlapping sign-ins B and C during A's refusal: B consumes `_deferredRevocation`, C sees none
      and exposes its session without awaiting `_revocationCleanup` → A's cleanup halts C's engines
      and drops C's alarms. Every sign-in waits the running cleanup right before exposure.
- **Test first:** `apps/app/test/features/auth/auth_repository_test.dart` — held `SecretStore.delete`;
  two delayed `onSessionUser` hooks. **Verify:** `npm run verify:task -- <those tests>` + auth K1.

### OPH-470 — Ring screen interaction restarts the 60-second quiet minute

Kritik yol: push-notifications. Found: phase-end review, `apps/app/lib/src/notifications/alarm_overlay.dart`
(`interacted()`).

- [ ] Only `silence()` calls `interacted()`; scrolling, pointer, keyboard and picker use on the
      ring screen do not → the sound resumes 60 s after the last action, not after the last touch.
      Wire a `Listener`/scroll notification and the sheets/pickers to `interacted()`.
- **Test first:** widget test — acknowledge one row, scroll at 50 s, no sound at 60 s, sound at 110 s.
  **Verify:** `npm run verify:task -- <that test>` + `check:notify-matrix`.

### OPH-478 — A widget completion leaves counts unchanged where the task was trimmed

Found: phase-end review (`apps/app/ios/Shared/AWSnapshotModel.swift`, `awCompleteInView`). Left
open: minor, heals on the next Dart publish.

- [ ] With 13 tasks due today the whole list holds 12 rows; completing task 13 from a project
      widget skips the whole-list bucket (its rows lack the id), so its count and `openToday`
      stay 13 in every day view. Decrement a counted bucket whose `more` > 0 when the task's due
      day puts it there, even when its row was trimmed.
- **Test first:** XCTest on the Mac — 13 due today, complete the 13th: counts read 12. **Verify:** K1.

### OPH-479 — Completing the next task can show "All caught up" while a trimmed task is open

Found: phase-end review (`apps/app/ios/Shared/AWSnapshotModel.swift`, `awNextOpen`). Left open: minor.

- [ ] 11 events then tasks A and B: the whole list draws 12 rows (A, `more` = 1). Completing A in
      a project widget searches only the drawn rows, finds none and drops `next`, so the
      lock-screen widget says "All caught up" while B is open. When a bucket has `more` > 0 keep
      a stale-but-honest `next` (or take it from another view's rows) instead of removing it.
- **Test first:** XCTest on the Mac with that fixture: `next` is B or kept. **Verify:** K1.

---

## Epic 37 — Widget fetches its own data (#50, PR-2)

The swiped-away half of #50: with the app force-quit, iOS runs neither background refresh nor a
silent push, so the widget extension fetches its own view with a read-only widget token. Starts
after Epic 36 merges. Owner decisions 2026-11-12: self-fetch is in scope; iOS background sync,
WidgetKit push and macOS self-fetch are not. Acceptance is softened (S-50): a change made elsewhere
appears within one WidgetKit reload (typically 15–60 min), with no minute guarantee. The grouping
fixture is born in OPH-463 and must reach the API lane before OPH-459. The self-fetch contract
(Keychain item, App Group keys, `/widget/snapshot` schema) is written in OPH-457 before any lane
starts; where a task and the contract differ, the contract wins. Swift tests run on the Mac:
`xcodebuild test -only-testing:RunnerTests` (iOS 27.2 simulator) + `flutter build ios --simulator
--debug`. Each commit body carries `Changelog:` and `Device:` lines; the shared docs are written
once, in OPH-465. No Dart or Swift lane runs `apps/api` integration suites (one shared MySQL).

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

## Epic 36 follow-up 2 — walkthrough leftovers (minor)

Minor findings of the web and iOS simulator walkthroughs (2026-11-12) that the two polish rounds
left open, each with the reason. None blocks an alarm: every surface can still be silenced and
saved. Each: failing test first where a test can see it, K1, `Changelog:` and `Device:` lines.

### OPH-473 — Turkish date and time pickers speak in "sen"

Found: web walkthrough (W-17), pre-existing. Left open: framework strings, not alarm work.

- [ ] Material's Turkish pickers say "Tarih seçin", "Saat seçin", "Saat girin" while the app says
      "sen". Pass our own `helpText` / field labels from i18n keys through `awShowTimePicker` and
      the date-picker call sites (`core/date_input.dart`, repeat dialog, ring "Saat seç").
- **Test first:** widget test in Turkish: the pickers show the informal labels. **Verify:**
  `npm run verify:task -- <that test>` + `check:i18n`.

### OPH-474 — Web: Noto Color Emoji and Noto Sans Symbols 2 answer 404

Found: web walkthroughs 1 and 2 (W-17). Left open: needs a release web build to measure.

- [ ] The console shows 404 for both families under `fonts/noto/`, then "Could not find a set of
      Noto fonts…"; such a glyph draws as a box. Check that `tool/mirror_noto_fallback.dart` fills
      both into the release build, and fix the mirror list or the build step that skips it.
- **Verify:** `web_fonts_offline_test.dart` + a release web build with no 404 in the console.

### OPH-475 — The iOS AlarmKit banner covers the in-app ring header

Found: iOS simulator walkthrough (IOS-02). Left open: the app cannot hide the system alert; the
fix is a layout choice that needs a device to measure.

- [ ] With the app in front, AlarmKit's own banner (Ertele/Durdur) sits over the ring screen's
      header ("3 ACİL HATIRLATMA · 11:42"). Either surface closes both, so nothing sticks; keep the
      header readable while the system alert shows (top inset or header below the banner area).
- **Verify:** golden of the ring screen with the inset · iPhone or simulator, foreground alarm.

### OPH-476 — A freshly installed iPhone lists `hasSession: false`

Found: iOS simulator walkthrough (IOS-05). Left open: auth critical path, not polish.

- [ ] After a clean install and sign-in the server's device row had `hasSession: false`, so
      removing that iPhone elsewhere may not sign it out (ADR-0069). Measure whether the first
      sign-in's refresh family is bound before the device row exists; bind it on registration or
      on the next refresh. (The raw "Dart/3.13 (dart:io)" name is already shown as "iPhone".)
- **Test first:** integration — sign in, register, list: `hasSession: true`. **Verify:** auth K1.

### OPH-477 — The device detail sheet's close control does not close it

Found: iOS simulator walkthrough (IOS-06). Left open: minor, outside the rounds' scope; the
dimmed area above still closes it.

- [ ] On iOS the element exposed as "Kapat" did nothing; tapping the dimmed area above the sheet
      closed it. The close control closes the sheet.
- **Test first:** widget test — tap the close control, the sheet is gone. **Verify:** K1.

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
- **Alarm ve widget adayları (Epic 36'dan, 2026-11-12 — ADR-0068/0069 ve ADR-0010/0015 notları):**
  iPhone'da çalan alarmı başka cihazdan susturma — Notification Service Extension +
  `AlarmManager.stop` spike'ı (AlarmKit'in uzak yolu yok, bugün yalnız iPhone'da susar); iOS
  `BGAppRefreshTask` + iOS sessiz push (ADR-0038 §8 kilitli Keychain; başka cihazda kurulan alarmın
  uygulama açılmadan kurulması da buna bağlı); WidgetKit push (doğrudan APNs, sahibin `.p8`
  anahtarı); Android başsız turun ön planla aynı anda token yenileme yarışı / refresh kirası; macOS
  widget'ının kendi verisini çekmesi; alarm-durdurma uyandırmasından onaylayan cihazı çıkarmak
  (sync olayı istemci kimliği taşımıyor).
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
