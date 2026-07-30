# AllisWellShare — iOS Share Extension (OPH-225, ADR-0023)

"Share to AllisWell" from any app. The extension does **zero** work of its own:
it hands the shared text/URL to the app through the App Group and redirects.
Every AI/network decision stays in the app — structurally, this process has no
code that could reach a model. v1 activates on **text and a single web URL**
only (`Info.plist` → `NSExtensionActivationRule`).

**Status: wired and verified** (2026-07-30). The Xcode target is committed in
`project.pbxproj` and a real `flutter build ios --release` produces
`Runner.app/PlugIns/AllisWellShare.appex` at the app's own version. Nothing
below needs running again for a normal build — it is here to re-apply the wiring
after a project regeneration, and to explain why each piece exists.

## What is in the repo

| File | Why |
| --- | --- |
| `ShareViewController.swift` | Empty `RSIShareViewController` subclass. |
| `Info.plist` | Activation rule (text + one web URL), `AppGroupId`, principal class. |
| `AllisWellShare.entitlements` | App Group `group.com.alliswell.alliswell`. |
| `../Flutter/AllisWellShare{Debug,Release,Profile}.xcconfig` | Base configs — see below. |
| `../scripts/wire_share_extension.rb` | Idempotent pbxproj wiring. |

## The four traps this setup already solves

Each of these was found by actually building, not by reading:

1. **Version parity.** App Store validation rejects an upload whose extension
   version differs from the app's. The extension therefore needs
   `MARKETING_VERSION = $(FLUTTER_BUILD_NAME)` **and** a base xcconfig that
   `#include`s `Generated.xcconfig`, or the variable resolves to empty. Same
   reason `Flutter/AllisWellWidget.xcconfig` exists.
2. **The `Flutter` group is virtual** (`name`, no `path`), so a file reference
   inside it must carry the full relative path (`Flutter/AllisWellShareRelease.xcconfig`).
   A bare filename makes Xcode look next to the `.xcodeproj` and fail with
   *"Unable to open base configuration reference file"*.
3. **The pod must not be compiled into the extension.** `receive_sharing_intent`
   also ships the Flutter plugin registrar, whose `addApplicationDelegate` is
   *unavailable in application extensions*. The Podfile therefore nests the
   target inside `Runner` with `inherit! :search_paths` (the plugin author's own
   recipe): the pod builds once for the app, and the extension links the
   embedded framework via `@rpath`.
4. **Embed phase ordering.** The appex must be copied by the existing
   **"Embed Foundation Extensions"** phase (the one the widget uses), which runs
   *before* Flutter's `Thin Binary` script. A second copy phase appended at the
   end lands after `Thin Binary` — which reads the whole `Runner.app` tree — and
   Xcode fails with *"Cycle inside Runner"*.

## Re-applying the wiring (only if the project is regenerated)

```bash
ruby ios/scripts/wire_share_extension.rb
```

The Podfile block is already in place:

```ruby
target 'Runner' do
  # …
  target 'AllisWellShare' do
    inherit! :search_paths
  end
end
```

Then `cd ios && pod install && cd .. && flutter build ios --release --no-codesign`.

## Before archiving

In Xcode, confirm both **Runner** and **AllisWellShare** carry the App Group
capability `group.com.alliswell.alliswell` and the same signing team — the
entitlement file is in the repo, but the provisioning profile must allow it.
(A `--no-codesign` build shows no entitlements; that is expected.)

## Verify on device

- Share a paragraph and a URL from Safari / Notes → "AllisWell" appears in the
  share sheet → tapping it opens the app with the bubble's chips (Görev yap ·
  Not al · Özetle · Soru sor) and the honest "Inbox'a kaydet".
- Cold start (app not running) and warm (already open) both land the payload —
  the binder in `HomeShell` only mounts signed in, so the payload waits for the
  session with no extra plumbing.
- With no AI provider configured, "Not al" and "Inbox'a kaydet" still work.
