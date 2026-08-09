# ADR-0027 — Attachment capture: `image_picker` for the photo library and the camera

- **Status:** Accepted (2026-08-10, OPH-244)
- **Context:** feedback round 17 #2 · binding UI rules [DESIGN.md §30](../DESIGN.md)
- **Related:** [ADR-0011](0011-attachments-r2-s3-storage.md) (attachment storage),
  [ADR-0023](0023-stt-and-share-intent-dependencies.md) (the precedent for a
  dependency ADR)

## Context

On an iPhone, "Add file" opened the document browser and photos were nowhere.
No permission dialog appeared either, which made it look like a permission bug.

It was neither. `pick_files_io.dart` called `FilePicker.pickFiles()` with no
`type:`, which is `FileType.any`, and file_picker 12's iOS handler
(`IOSFilePickerHandler.swift:65-92`) routes `any` to
`UIDocumentPickerViewController` while only `image`/`video`/`media` reach
`PHPickerViewController`. The missing dialog was correct behaviour: PHPicker
runs out of process and asks for nothing.

Fixing the call alone would have satisfied iOS and left Android wrong.
`file_picker`'s Android side (`FileUtils.kt:180-250`) builds
`Intent.ACTION_GET_CONTENT` for `image/*`, `video/*` and `media` — never
`ACTION_PICK_IMAGES`/`PickVisualMedia`. So `FileType.media` gives the system
photo picker on iOS and a document browser on Android, and DESIGN §30 A2 names
the Android Photo Picker explicitly. `file_picker` also has no camera at all,
and the owner asked for one.

## Decision

**Route by intent, across two packages.** `AttachSource` (a pure enum in
`features/files/data/attach_source.dart`) is a required argument to the picker
seam; media-library and camera sources go to **`image_picker`**, everything else
stays on **`file_picker`**'s document browser.

Add `image_picker` + `image_picker_android` (direct, see Consequences) and
declare **`NSCameraUsageDescription`**. Declare no Android permission at all.

## Alternatives

**Stay on `file_picker` alone.** Rejected: measured, it cannot open the Android
Photo Picker and has no camera. It would satisfy the letter of the bug report
(iPhone photos) and leave Android on the path the report was about.

**Use the `camera` package for capture.** Rejected on its manifest, which is the
whole reason to look: `camera_android_camerax-0.6.30/android/src/main/AndroidManifest.xml`
declares `CAMERA`, `RECORD_AUDIO` **and** `WRITE_EXTERNAL_STORAGE`. That is a
direct DESIGN §30 A3 violation and a Play photo/video-policy risk, in exchange
for a full preview UI we do not want. Written down here so it stays rejected.

**Ship no camera.** The honest fallback if the dependency had cost anything. It
did not: see below.

**Fear `image_picker` over Play rejections.** The planning round flagged
[flutter#171493](https://github.com/flutter/flutter/issues/171493) /
[#171494](https://github.com/flutter/flutter/issues/171494) as a reason to avoid
it. Measured instead of remembered: five `image_picker_android` versions in the
local pub cache (0.8.12+4 … 0.8.13+19) declare **zero** `<uses-permission>`;
their manifest contributes a `FileProvider`, one xml resource and a disabled GMS
service. Those reports are about the apps' own manifests. The fear was
misplaced — the gate below stays anyway.

## Consequences

- **`image_picker_android` is a direct dependency, not transitive.** The Android
  Photo Picker is **off by default** (`image_picker_android.dart`:
  `useAndroidPhotoPicker = false`); reaching `ImagePickerPlatform.instance` to
  turn it on requires the implementation package. Forgetting that line puts the
  app straight back on `ACTION_GET_CONTENT` — the bug this ADR exists to fix.
- **The camera is mobile-only, as a correctness requirement.** The desktop
  implementations extend `CameraDelegatingImagePickerPlatform`, which **throws
  `StateError`** for `ImageSource.camera` with no delegate. `attachMenuSources`
  therefore never offers it off iOS/Android; a direct call answers "picked
  nothing" rather than crashing.
- **Camera captures are renamed.** `XFile.name` is the plugin's temp path
  (`image_picker_5B1F….jpg`); `cameraCaptureName` produces `IMG_20260810_003215.jpg`
  so raw plumbing never reaches a file row (DESIGN §10 F6).
- **v1 captures one photo.** Video capture is a second product decision, parked.
- iOS gains exactly one string, `NSCameraUsageDescription`. Photos still ask for
  nothing.

## Zorlama (how this is enforced)

Two layers, because the first one is silent when it misses.

1. **Manifest-merger removal.** `android/app/src/main/AndroidManifest.xml`
   carries `tools:node="remove"` for `CAMERA`, `READ_MEDIA_IMAGES`,
   `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED`,
   `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE`. The `CAMERA` line does
   double duty: `ImagePickerUtils.isPermissionPresentInManifest` stays false
   forever, so image_picker can never enter its runtime-permission branch no
   matter what a future plugin injects.
2. **`scripts/android/assert-permissions.sh`** diffs the **release APK's binary
   manifest** (what Play scans — not the `merged_manifests` intermediate)
   against a committed allowlist, as an exact set. A denylist would only catch
   the permissions we already thought of.

   The allowlist was populated from a real build, never guessed — it contains
   entries nobody would have predicted (`ACCESS_ADSERVICES_*`, `AD_ID`,
   `USE_BIOMETRIC`, `READ_GSERVICES`). First run after this ADR: **18
   permissions, none of them media or camera.**

   ```bash
   bash scripts/android/assert-permissions.sh
   ```

**No Dart test can verify any of this.** The merged manifest only exists in a
build, which is why the gate is a script and a CI job rather than a unit test.
