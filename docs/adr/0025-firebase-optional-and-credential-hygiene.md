# ADR-0025 — Firebase is optional, and its credentials are not in the repository

- **Status:** Accepted
- **Date:** 2026-07-31
- **Related task:** OPH-230

## Context

AllisWell needs Analytics, Crashlytics and Performance to be publishable as a
commercial product: without crash reporting, a store review that says "it crashes
on launch" is unanswerable. It also has a public source tree that anyone may fork
and self-host.

Those two facts collide at exactly one point — the Firebase config files. The
standard Flutter setup (`flutterfire configure`) generates
`lib/firebase_options.dart` and drops `google-services.json` /
`GoogleService-Info.plist` into the platform folders, and every tutorial commits
all three. Doing that here would publish the identifiers of the maintainer's
billed project in a repository designed to be copied.

The lazy inverse is just as bad: gitignore the files and let the build break for
everybody else. `com.google.gms.google-services` **fails the build outright**
when `google-services.json` is absent, so a fresh clone would not compile.

## Decision

Firebase is a **runtime-optional** dependency, and the opt-in signal is the
presence of the platform config file.

1. **No `firebase_options.dart`.** `Firebase.initializeApp()` is called with no
   options; the native SDK reads its own config file. Keys therefore never enter
   Dart, and never enter git.
2. **The Gradle plugins are applied conditionally** — `android/app/build.gradle.kts`
   checks `file("google-services.json").exists()` before applying
   google-services, Crashlytics and Performance.
3. **`AwFirebase.bootstrap()` never throws.** A missing config leaves
   `isConfigured` false; every helper on the class becomes a no-op, so call sites
   need no guards and no feature has to know.
4. **`.example` templates are committed** for all three config files, documenting
   the shape and pointing at `docs/FIREBASE.md`.
5. **Web has no implicit config** — without `--dart-define`d options the web
   build simply has no Firebase.
6. **iOS gets a Podfile fallback.** Xcode cannot express "copy this resource if
   it exists": the plist is a required build input, so a clone without one fails
   before compiling. The Podfile therefore copies the committed `.example` into
   place when the real file is missing. Verified by deleting the plist and
   building — which is how the gap was found, after the ADR had already claimed
   the fresh-clone guarantee held on every platform.

## Alternatives considered

- **Commit the config files.** What almost every Flutter repo does. Rejected:
  the whole point of a public tree here is that forks are expected, and a fork
  inheriting our project id sends its users' analytics to us.
- **Encrypted secrets in-repo (git-crypt, SOPS).** Solves publication, not the
  fork problem — a fork still cannot decrypt, so it still needs the fallback path
  this ADR builds. Extra machinery for no additional outcome.
- **Generate `firebase_options.dart` in CI from secrets.** Keeps keys out of git,
  but a local `flutter run` would then have no Firebase unless every contributor
  reproduced the CI step. The config-file approach gives the same guarantee with
  a file copy.
- **Drop Firebase; self-host analytics.** Defensible for analytics, not for
  crash reporting: symbolicated iOS/Android crash grouping is not something worth
  rebuilding to avoid a dependency.

## Consequences

- A fresh clone builds and runs with **no Firebase**, and says so once in the log.
  On iOS this needs the Podfile fallback above; on Android the Gradle gate is
  enough. The claim is checked by removing the config file and building, not
  assumed.
  This is the normal state for contributors and self-hosters, not a broken setup.
- The maintainer's release builds need the three files present on the build
  machine or in CI secrets — they are not in git, so a release pipeline that
  forgets them ships a build with no crash reporting and **no error**. That is the
  cost of this design; `docs/FIREBASE.md` §2 is the checklist against it.
- Turning telemetry off entirely is deleting three files. Turning it off at
  runtime is `AwFirebase.setCollectionEnabled(false)`.
- **PRIVACY.md gained real obligations**: Analytics, Crashlytics and Performance
  are new processors on the hosted builds, and the store data-safety declarations
  had to change with them. A future contributor adding an event must keep that
  section true.
