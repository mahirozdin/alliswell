# Firebase — optional, and never in this repository

AllisWell uses Firebase for **Analytics, Crashlytics, Performance and Auth**.
All four are optional at runtime. None of the credentials that point at the
maintainer's project are in this repository, and none ever will be.

If you are here because you forked AllisWell and want your own telemetry, §2 is
the whole job.

---

## 1. How "optional" is actually implemented

This is the part worth understanding before changing anything, because the
obvious setup — `flutterfire configure`, commit everything — breaks both
promises at once: it puts the maintainer's project identifiers in a public repo
_and_ makes the app impossible to build without them.

| Concern                                   | How it is handled                                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Dart never carries keys                   | There is **no `firebase_options.dart`**. `Firebase.initializeApp()` is called with no options, so the native SDK reads the platform's own config file. That file is gitignored; the Dart is not.                                                                                                                                                                                                             |
| A missing config must not break the build | The `google-services`, Crashlytics and Performance Gradle plugins are applied **conditionally** — `android/app/build.gradle.kts` checks whether `google-services.json` exists. Applying `google-services` without one fails the build outright, which would mean nobody could compile a fresh clone.                                                                                                         |
| A missing config must not break the app   | `AwFirebase.bootstrap()` (`lib/src/core/firebase/firebase_bootstrap.dart`) catches the initialisation failure, leaves `isConfigured` false, and returns. Every helper on it is then a no-op, so call sites need no guards.                                                                                                                                                                                   |
| Web                                       | Firebase web cannot discover anything by itself. Without `--dart-define`d options the web build simply has no Firebase — an explicit skip, not a caught error.                                                                                                                                                                                                                                               |
| iOS needs a file to exist                 | Xcode's Copy Bundle Resources treats `GoogleService-Info.plist` as a **required build input**, and unlike Gradle it cannot be made conditional — a clone without one fails with "Build input file cannot be found" before any Dart compiles. So the **Podfile materialises the committed `.example`** when the real file is absent. `pod install` runs inside every `flutter build ios`, so this self-heals. |
| Auth must work without any of it          | Sign-in verifies **the provider's** ID token on our own server, never a Firebase token (see [ADR-0026](adr/0026-social-sign-in.md)). A self-hoster with no Firebase project still gets Google and Apple sign-in by configuring client IDs; a self-hoster with neither still gets e-mail and password.                                                                                                        |

The gitignored files, each with a committed `.example` beside it:

```
apps/app/android/app/google-services.json
apps/app/ios/Runner/GoogleService-Info.plist
apps/app/macos/Runner/GoogleService-Info.plist
```

**On whether these are "secrets".** They are not passwords — they ship inside
every installed app and both vendors treat them as public identifiers. They are
kept out of the repository because they _point at a billed project_, not because
they unlock it. What actually protects a Firebase project is App Check, Security
Rules and the registered bundle IDs / SHA-256 fingerprints. Configure those. Do
not rely on a file being gitignored.

## 2. Wiring up your own project

```bash
# 1. Create it (or use one you have)
firebase projects:create your-project-id --display-name "Your App"

# 2. Register the apps. The identifiers must match what you build.
firebase apps:create ANDROID "Your App Android" \
  --package-name com.example.yourapp --project your-project-id
firebase apps:create IOS "Your App iOS" \
  --bundle-id com.example.yourapp --project your-project-id

# 3. Pull the config files into place. `firebase apps:list` prints the app ids.
firebase apps:sdkconfig ANDROID <androidAppId> --project your-project-id \
  --out apps/app/android/app/google-services.json
firebase apps:sdkconfig IOS <iosAppId> --project your-project-id \
  --out apps/app/ios/Runner/GoogleService-Info.plist

# macOS shares the iOS registration when the bundle id is the same.
cp apps/app/ios/Runner/GoogleService-Info.plist apps/app/macos/Runner/
```

Then in the Firebase console, enable what you want under **Analytics**,
**Crashlytics** and **Performance**. Nothing else in the repo changes: the
Gradle gate notices the file and applies the plugins on the next build.

**iOS minimum version.** Firebase 12.x requires **iOS 15.0**; the project and
Podfile are set to it. Dropping below that is what produces CocoaPods'
"required a higher minimum deployment target".

**Google Analytics** is the same product as Firebase Analytics here — a Firebase
project with Analytics enabled _is_ a GA4 property. There is no second SDK to
add.

Xcode targets need `GoogleService-Info.plist` added to the **Runner** target's
"Copy Bundle Resources" once (it is a file reference, so this survives the file
being replaced). Crashlytics on iOS also wants a run-script phase uploading dSYMs
— see Firebase's own iOS setup page; it is the one step the CLI cannot do.

### Google Sign-In needs two more things

- **SHA fingerprints (Android).** Until the release _and_ debug SHA-1s are
  registered on the Android app, `google-services.json` comes back with an empty
  `oauth_client` list and sign-in fails at runtime with a developer error. If you
  use Play App Signing, the certificate Play re-signs with must be registered too
  — otherwise sign-in works in your own build and fails for everyone who
  installs from the store.
- **The iOS callback URL scheme.** iOS cannot return from the Google sheet
  without `REVERSED_CLIENT_ID` declared as a URL scheme. `Info.plist` (committed)
  holds `$(GOOGLE_REVERSED_CLIENT_ID)`; the Podfile reads the real value out of
  the plist and writes `ios/Flutter/Firebase.xcconfig`, which is gitignored. No
  project identifier is committed, and a build with no config file simply
  produces no scheme.

**The token's audience.** `SocialSignIn` passes the **web** client id as
`serverClientId`, so the ID token has one audience on every platform. That is why
the server needs only `SIGN_IN_GOOGLE_WEB_CLIENT_ID` — the per-platform Android
and iOS clients never appear as an audience and do not belong in the server's
environment.

**Fetching config with the CLI:** `firebase apps:sdkconfig … --out <file>` can
write a **cached** copy that predates your latest console change. Printing to
stdout returns the fresh one. If a config comes back with no `oauth_client`
after you have added fingerprints, that is what happened — pipe stdout to the
file instead.

## 3. Turning it off

For a build with no telemetry at all, delete the config files. That is the whole
procedure — the app reports itself unconfigured and runs.

To keep Firebase but stop collection at runtime (a privacy toggle, a regional
build), call:

```dart
await AwFirebase.setCollectionEnabled(false);
```

It reaches Analytics, Crashlytics and Performance together.

## 4. What is actually collected

This has to stay in step with [PRIVACY.md](PRIVACY.md) — if you change one,
change the other.

- **Analytics** — screen names, app version, coarse device model, country-level
  region, and the events the app logs explicitly. `AwFirebase.setUser()` attaches
  **AllisWell's own ULID**, never an e-mail address and never anything a user
  typed.
- **Crashlytics** — stack traces, OS and device model, and the same ULID. Task
  titles, note bodies and file names are never attached to a report.
- **Performance** — network request durations by URL pattern, and screen render
  times. No request bodies.
- **Auth** — when a user signs in with Google or Apple, that identity is also
  registered in Firebase Auth so a crash report can name the account. The
  AllisWell session does not depend on it (ADR-0026).

Self-hosters: your instance's users are **your** data subjects. If you enable
Analytics on a fork you are the controller of what it collects, and your own
privacy policy has to say so.

## 5. Related

- [ADR-0025 — Firebase is optional, and its credentials are not in the repository](adr/0025-firebase-optional-and-credential-hygiene.md)
- [ADR-0026 — Sign in with Google and Apple](adr/0026-social-sign-in.md)
- [PRIVACY.md](PRIVACY.md) · [SELF-HOSTING.md](SELF-HOSTING.md)
