# ADR-0009 — Localization (i18n): JSON locales, device/browser detection, persisted override

- **Status:** Accepted
- **Date:** 2026-07-17
- **Related task:** Epic 11 (OPH-120…128)
- **Related:** feedback round 5 (user request: strip hardcoded strings, ship a
  language mechanism where locales are plain JSON, auto-pick the device/browser
  language with an English fallback, and let the user pin a language from
  Settings); BLUEPRINT §12.9, §15.5; docs/DESIGN.md §9

## Context

Every user-facing string in the Flutter app is hardcoded English (≈120 literals
across ~19 files: `Text('Home')`, `'Overdue'`, `'Sign out'`, `HomeBucketLabel`,
snackbars, hints…). There is NO localization layer — the only
`localizationsDelegates` wired in `app.dart` are Flutter Quill's, purely so the
editor renders. The DB already carries `users.locale` (`VARCHAR(16)` default
`tr-TR`) and `GET /me` returns it, but nothing reads it. The single Flutter
codebase is also the WEB build, so one i18n system serves app + web.

The user's requirements are specific and binding:

1. Extract all hardcoded strings behind a translation mechanism.
2. **Locales are plain JSON** that can be *provided/dropped in* — a self-hoster
   (or the user) can add a language by supplying a JSON file, not by touching
   Dart. English `en.json` is the fallback/base.
3. **Auto-detect** the device language: a TR device with a `tr.json` present
   opens in Turkish; anything unsupported falls back to English.
4. A **Settings** language picker sets a *persistent* override that wins over the
   device language and survives restarts.
5. On **web**, the browser language is the default, and the Settings override
   still persists and wins.
6. Ship `en.json` + `tr.json` to start.

This is a new dependency category and a cross-cutting architectural choice, so it
needs an ADR (AGENTS.md rule 6).

## Decision

1. **Engine: a small app-owned, SYNCHRONOUS JSON store** (`lib/src/i18n/i18n.dart`,
   `AwI18n`). Translations live as JSON under `assets/i18n/` (`en.json` = base/
   fallback, `tr.json`) and are read into memory **once before `runApp`**
   (`await AwI18n.instance.boot()` in `main()`), so `'key'.tr()` is a synchronous
   map lookup at build time — no `FutureBuilder`, no first-frame flicker. (The
   engine is synchronous ON PURPOSE: the app has a large fake-async widget-test
   suite, and an async translation loader forces every full-app test through
   `runAsync` — see Alternatives.) Details:
   - **Device/browser detection:** with no saved override, `AwI18n.boot()` picks
     the first supported entry of `PlatformDispatcher.instance.locales` (the
     browser languages on web), else the fallback. `resolveInitialLocale` is a
     pure, unit-tested function (override → device → `en`).
   - **Persistent override:** the Settings picker calls `AwI18n.setLocale(locale)`,
     which persists the choice to `localKv` (SharedPreferences; localStorage on
     web) and switches at runtime by rebuilding the app; `useSystemLocale()`
     clears it and follows the device again.
   - **Fallback chain (per key):** active locale → `en` → the key itself. A key a
     locale hasn't translated (or an unknown language file) resolves to the
     English value, so a partial translation still ships.
   - **Runtime switch:** `AwI18n` is a `ChangeNotifier`; `app.dart` wraps
     `MaterialApp` in a `ListenableBuilder` so a language change re-resolves every
     `.tr()` and re-localizes Material/Cupertino. `{name}` placeholders are filled
     from `args`.
2. **The engine lives behind ONE seam.** Widgets use the ergonomic `'key'.tr()`
   extension from `lib/src/i18n/i18n.dart`; nothing else touches the store, so it
   stays swappable and there is one place for plural/param helpers. Keys use a
   dotted namespace: `home.title`, `task.status.open`, `common.save`,
   `settings.language`, `widget.bucket.overdue`, `error.<CODE>`.
3. **`localizationsDelegates` cover the built-in widgets.** `app.dart` sets
   `GlobalMaterialLocalizations/GlobalWidgetsLocalizations/
   GlobalCupertinoLocalizations` (from `flutter_localizations`, SDK) AND the
   existing `FlutterQuillLocalizations.localizationsDelegates`; `MaterialApp.locale`
   is `AwI18n.instance.locale` and `supportedLocales` is `awSupportedLocales`. App
   strings come from `AwI18n`, not a delegate. No third-party i18n package.
4. **API stays language-neutral; the app localizes.** Endpoints keep returning a
   stable machine-readable `code` (e.g. `AUTH_INVALID_CREDENTIALS`); the app maps
   `code → error.<CODE>` in the locale files, falling back to the server `message`
   then a generic string (`ApiException(code, message)` already carries both). No
   server-side i18n in v1.
5. **Account-level language follows the user across devices.** A new
   `PATCH /api/v1/me { locale }` persists the picked locale to `users.locale`; on
   sign-in the app seeds its initial locale from `GET /me.locale` when the device
   has no saved override. The DEVICE override still wins locally (offline-first).
   This is the "kalıcı dil değişikliği" that survives a reinstall / new device.
6. **Shipped locales v1:** `en` (base) + `tr`. Adding a language = drop
   `assets/i18n/<code>.json`, add the `Locale` to `supportedLocales`, register
   the asset. (Runtime, no-rebuild provisioning — loading user/served JSON via
   easy_localization's custom asset loaders, e.g. from the API or a file — is
   deferred to v2; the base mechanism is designed not to preclude it.)

## Alternatives considered

- **`easy_localization` (the initial pick, reverted in OPH-120).** It matches the
  JSON/device/fallback/persist requirements out of the box and was implemented
  first. Rejected after it proved **incompatible with the existing widget-test
  suite**: its translations load asynchronously via a `LocalizationsDelegate`, and
  under flutter_test's fake-async clock that load does not complete during
  `pumpAndSettle` — the `Localizations` widget blocks the whole app subtree, so
  ~40 full-app tests rendered nothing (and once strings became `.tr()`, they'd
  read raw keys). The only fixes were per-test `runAsync` gymnastics (fragile, a
  fixed-delay fudge) or reaching into the package's `src/` to pre-seed its global
  store. For a repo whose quality bar is "no student-project shortcuts," a
  synchronous store we own is cleaner than fighting the package's async lifecycle.
  The custom store is ~180 lines, fully unit-tested, and keeps every user
  requirement.
- **Flutter gen-l10n / `.arb` (official).** Rejected: ARB is not the JSON the
  user asked to "provide," it is compile-time only (no drop-in language), and its
  ergonomics (generated `AppLocalizations.of(context)`) are heavier for a
  self-hoster adding a language.
- **`slang` (typed codegen from JSON).** Strong DX and compile-time safety, but
  each locale is compiled into Dart, so **a user cannot add a language by dropping
  a JSON at runtime** — an explicit requirement. Rejected for that reason.

## Consequences

- **Every UI string moves behind a key.** A one-time extraction sweep across the
  ~19 screen files (Epic 11), plus a discipline rule: no new hardcoded
  user-facing string — enforced by a lint/CI grep (`scripts/i18n/check.*`) that
  fails on raw `Text('literal')` outside allowlisted spots (brand name, debug).
- `HomeBucketLabel.label` and other enum-derived strings become key lookups; the
  widget layer (ADR-0010) consumes the SAME localized strings — the app writes
  already-translated text into the widget snapshot, so the native widget needs no
  translation bundle. This makes i18n a natural prerequisite of the widget epic.
- Adds only `flutter_localizations` (SDK) — **no third-party i18n package.** New
  code `lib/src/i18n/i18n.dart` (`AwI18n` store + `String.tr()`), new asset dir
  `assets/i18n/`. `main()` gains `await AwI18n.instance.boot()` before `runApp`.
  Tests load the JSON off disk synchronously via a `flutter_test_config.dart`
  bootstrap (an `awI18nAssetReader` seam), so `.tr()` resolves under a plain
  `pumpAndSettle` and the existing suite needed **zero** changes.
- New endpoint `PATCH /me` (small, Ajv-validated, `locale` allow-list) + a sync
  of the picked locale. `users.locale` finally has a writer.
- Longer translations (German-style expansion, and Turkish agglutination) can
  overflow tight layouts; the design already avoids fixed-width labels
  (truncation + tooltip per DESIGN §4), and DESIGN §9 makes this a review rule.
- **RTL is out of scope for v1** (en + tr are both LTR). The stack does not
  preclude it — adding an RTL `Locale` flips `Directionality` automatically — but
  RTL layout review is a v2 task.
- Tests: golden/text tests assert keys resolve in both locales and that a missing
  `tr` key falls back to `en`; a locale-switch widget test flips the app and
  re-reads a visible label.
