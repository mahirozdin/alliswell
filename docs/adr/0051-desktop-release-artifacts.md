# ADR-0051 — Windows and Linux desktop builds on every release

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-370

## Context

Web, Google Play and the App Store were ready, but the desktop targets were "build from
source": the v1.17.0 release carried one asset, the web bundle. A developer who will never
self-host could not open the app on a PC. The owner asked for every desktop platform on the
release stage except macOS, and for packaging that stays boring.

Constraints: the release must never be held back by a desktop build (`v*` tags deploy
production, LESSONS `ci-release`); there is no code-signing certificate; the binaries talk to
alliswell.space by default and can be pointed at any server from the sign-in screen, so one
build serves every instance.

## Decision

- `release.yml` gets a `desktop` matrix job (`needs: gate`; `ubuntu-24.04` → Linux,
  `windows-2025` → Windows; Flutter pinned to 3.44.0 as in CI) that runs
  `flutter build <os> --release --build-name=<tag version>`, after the same tag ↔ pubspec ↔
  `kAppVersion` check the web release makes.
- Assets: **`alliswell-linux-x64.tar.gz`** (the Flutter bundle; the job fails when `ldd` of the
  binary reports a missing library) and **`alliswell-windows-x64.zip`** (the Release folder),
  plus `alliswell-desktop-SHA256SUMS.txt`.
- **Asset names carry no version**, so README and landing link
  `releases/latest/download/<name>` and never go stale. The version is the archive's top folder
  (`alliswell-<version>-<os>-x64/`) and is compiled into the binary (Windows file/product
  version, Settings › About).
- The Windows zip carries the **VC++ runtime app-local** (`msvcp140.dll`, `vcruntime140.dll`,
  `vcruntime140_1.dll`, copied from the runner's Visual Studio via vswhere): Flutter's bundle
  does not, and a PC without the redistributable fails with "MSVCP140.dll was not found".
- A separate `desktop-attach` job (`needs: [release, desktop]`, runs unless cancelled once
  `release` succeeded) uploads with `gh release upload --clobber`, then **goes red when either
  leg failed** after attaching what exists. Neither job is in `deploy`'s `needs`: a desktop
  failure never blocks production.
- **Unsigned.** README and the landing cards say SmartScreen asks once (More info › Run anyway).
- The app side of the same change: Windows notification settings (without them the plugin
  throws and every local reminder failed), Google sign-in hidden on Windows/Linux (google_sign_in
  has no implementation there), the home_widget callback registered only where the plugin
  exists, and the shells branded (title, `Runner.rc`, an `app_icon.ico` derived by
  `scripts/design/branding_icons.py`).

## Alternatives considered

- **AppImage / .deb / Flatpak.** AppImage needs appimagetool and FUSE on the user's machine;
  .deb needs dependency metadata per distribution; Flatpak needs a manifest and a runtime.
  None is boring yet — the tar.gz runs on any glibc desktop with GTK 3.
- **MSI / MSIX installer.** MSIX would give package identity (Action Center clean-up, a real
  Start entry) but is only worth shipping signed. A zip has no install step to go wrong.
- **Versioned asset names** (like the web bundle). Every README/landing link would rot at the
  next release or need a rewrite per release.
- **Desktop builds inside the `release` job.** One failing Windows configure step would have
  blocked the web release and the deploy behind it.
- **macOS.** Excluded by owner decision (would need Developer ID signing and notarisation).

## Consequences

- The first Windows build happens on the next tag — it cannot be built on the Linux machine the
  work was done on. A failure leaves that release without the zip; deploy is unaffected and
  `Attach desktop downloads` shows red.
- README links return 404 until that tag exists, and for the minutes between the Release being
  created and `desktop-attach` finishing.
- The unpackaged Windows build cannot remove an already-shown toast from Action Center;
  scheduled toasts are still cancelled (docs/NOTIFICATIONS.md §3).
- Linux users need GTK 3, libsecret with a running keyring (the session lives there) and
  GStreamer; documented in the README, not bundled.
- Follow-ups for the owner, when wanted: an Authenticode certificate (or Azure Trusted Signing)
  plus a signtool step removes the SmartScreen prompt; a Linux `.desktop` file and icon, an
  installer or macOS downloads would each be a new decision.
