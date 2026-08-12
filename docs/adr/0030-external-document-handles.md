# ADR-0030 — Owning somebody else's file: durable handles, an in-repo plugin, and where writing is refused

- **Status:** Accepted (2026-08-12, OPH-255)
- **Context:** feedback round 17 #3 · [DESIGN §29.5 W1–W6](../DESIGN.md) ·
  [MARKDOWN.md §6](../MARKDOWN.md) · [TASKS Epic 24](../TASKS.md)
- **Related:** [ADR-0028](0028-markdown-document-model-and-renderer.md) (the
  note model this rests on), [ADR-0027](0027-attachment-capture-image-picker.md)
  (the precedent for deciding a dependency by measurement),
  [ADR-0013](0013-local-first-search.md) (the "this layer has to be ours" shape),
  [ADR-0011](0011-attachments-r2-s3-storage.md) (files we own, which this
  is deliberately *not*)

## Context

Round 17 asked for the app to open a `.md` file from the user's own computer,
edit it, and **save it back**. DESIGN §29.5 governs it with six rules, and
opens by naming the stakes: this is the only feature in the round that can
destroy a user's data.

Planning OPH-251 measured three things that changed the shape of the work.

**1. `file_picker` hands iOS a copy, so the picker has to be ours.**
`IOSFilePickerHandler.swift:249` constructs
`UIDocumentPickerViewController(..., asCopy: !asDirectoryPicker)`, and
`asDirectoryPicker` is false when picking files — so it is always `asCopy:
true`. Whatever we wrote would land in a temp copy; the user's file would never
change. This is not a bug to work around, it is the package's contract.

**2. macOS cannot write at all today.** `macos/Runner/{DebugProfile,Release}.entitlements`
have `app-sandbox = true` and **no file entitlement of any kind** — not
`files.user-selected.read-only`, not `read-write`, not
`files.bookmarks.app-scope`. The acceptance criterion ("a README.md on a Mac is
opened, edited, saved, and the file on disk has changed") is presently
impossible. Worse for diagnosis: a missing entitlement does not error. The
sandbox simply returns read-only, which is **indistinguishable from a file that
is legitimately read-only**.

**3. Our own decoder would corrupt the file.** `markdown_source.dart` reads with
`Utf8Decoder(allowMalformed: true)`. That is the right call for *reading* — one
stray byte should not cost the whole document — but the moment a write exists,
the same line turns every non-UTF-8 byte into U+FFFD and writes those
replacement characters back into somebody's file. W4 calls this by its name:
data loss with good intentions.

Against those, one measurement went the other way. `note_document.dart`'s
`markdown` getter returns `source.text` **verbatim** for a markdown-canonical
note, never through Delta — its comment already says this is what makes saving
back honest. So W4's hard half (a WYSIWYG round-trip reflowing a hand-formatted
file) was solved in OPH-248. What remains is *encoding* fidelity and a format
gate.

## Decision

### 1. A durable handle, stored device-locally, never synced

An external document is identified by an `ExternalDocHandle` — an opaque
platform-shaped `token` plus its kind: a base64 security-scoped bookmark on
Apple, a `content://` URI on Android, a plain path where there is no sandbox.

Handles live in `LocalKv` (`alliswell_external_recents`), **not in the synced
database**. A bookmark is meaningful only to the device and app that minted it;
syncing one would hand another device a token it cannot resolve and a recents
list full of dead rows. W6 is a per-device promise.

### 2. Our own plugin: `alliswell_docref`

An in-repo path package at `apps/app/packages/alliswell_docref/`, channel
`alliswell/docref`, laid out exactly like `alliswell_eventkit` — including its
verified trick: the macOS `Sources/` directory is a **symlink** to the iOS one,
so a single Swift file serves both Apple platforms behind `#if os(...)`.
Flutter's tooling wires the podspec for iOS and macOS with no pbxproj surgery
(`pubspec.yaml`), and Android gets registration without touching
`MainActivity.kt`. Platforms with no implementation degrade to
`ExternalUnreachable(unsupportedPlatform)` — the same honest-unavailable idiom
the AlarmKit bridge uses.

The plugin stays thin: it moves bytes and reports facts. Every policy decision
stays in Dart, where it is testable.

### 3. W3 lives in the type system, not in a convention

```
sealed class ExternalAccess
  ExternalWritable(saver)      ExternalReadOnly(reason)      ExternalUnreachable(reason)
```

The `saver` exists **only** on the writable arm. A UI that switches over
`ExternalAccess` therefore has nothing to bind a save action to in the other two
arms — the compiler enforces "absent, not present-and-failing" (§22). A boolean
would have let the button be built and disabled, which is the dead affordance
the rule forbids.

Save outcomes are sealed for the same reason: `SaveSucceeded` ·
`SaveConflict(onDisk)` · `SaveLostAccess` · `SaveFailed`. `SaveIntent.force` is
reachable only from the conflict branch, so **a silent overwrite is not
expressible**.

### 4. W4 in code: strict on the write edge, lossy only for display

The plugin returns raw bytes; Dart decodes with `allowMalformed: **false**`.

- A leading `EF BB BF` is stripped, recorded as `utf8Bom`, and **re-emitted on
  save**. Silently dropping a BOM is a byte change nobody asked for.
- A `FormatException` means `notText`. We do **not** guess Latin-1. The file
  still **opens** — refusing to show a file is worse than refusing to write it —
  decoded lossily for display only, and its access is
  `ExternalReadOnly(notUtf8)`.
- Writing back is offered only when the note is markdown-canonical **and** the
  encoding is text: one pure predicate, `canWriteBack`.
- No line-ending normalisation, no inserted trailing newline.

### 5. W5: stamp at open, compare at save, inside the write

An `ExternalDocStamp` carries `sha256` (via `crypto`, already a direct
dependency; bounded by the existing 2 MB ceiling), `sizeBytes` and
`modifiedAt`, with a stated order of authority: mtime is trustworthy on Apple
and **not on Android**, where SAF's `COLUMN_LAST_MODIFIED` is optional and cloud
providers return null. Where mtime is absent, the hash decides.

The comparison happens **natively, inside the coordinated write** — the one
deliberate exception to "no policy in native", because it is the only place
check-then-write can be atomic.

### 6. Atomicity is asymmetric, and we say so

**Apple is crash-safe.** `NSFileCoordinator(.forReplacing)` around
`data.write(to:options:.atomic)`. We do **not** hand-roll a temp file: the
sandbox grant covers the *selected file*, not its directory, so a sibling temp
file fails on a real signed build.

**Android is not, and cannot be.** There is no rename across a SAF URI.
`openOutputStream(uri, "wt")` truncates and streams; a crash between truncation
and the last byte leaves a partial file **and the original is gone**. Mitigated,
not solved: one buffered write, and the previous bytes copied to app-private
storage first (`filesDir/external_recovery/<sha>.md`) so a torn save is
recoverable on next launch. `createDocument` + delete was rejected — it changes
the URI, invalidating the persisted grant and every recents entry.

### 7. Two macOS entitlements, and zero Android permissions

macOS gains `com.apple.security.files.user-selected.read-write` and
`com.apple.security.files.bookmarks.app-scope` in both entitlement files.
Without the first the panel grants read-only; without the second a
security-scoped bookmark cannot be minted at all.

Android gains **no `<uses-permission>`**. SAF is permissionless by design, and
`scripts/android/assert-permissions.sh` must keep passing byte-identical — the
ADR-0027 guarantee is not spent here.

## Alternatives considered

| Option | Why it lost |
| --- | --- |
| Keep `file_picker` and write to what it returns | Measured: iOS gets a copy (`asCopy: true`, always). We would write to a temp file and report success. |
| `file_selector` (Flutter team, federated) | Same copy semantics on iOS, and still no write, no bookmark, no stat. It solves the half we already have. |
| Bookmarks in the synced DB, so recents follow the user | A bookmark resolves only on the device that minted it. Syncing it produces a list of rows that cannot open. |
| Guess the encoding (Latin-1 fallback) when UTF-8 fails | A guess that is wrong writes a corrupted file and looks like success. Refusing the write is the only honest option W4 allows. |
| Refuse to OPEN a non-UTF-8 file | Punishes reading for a writing problem. The file opens read-only and the banner says why. |
| `DocumentFile` (androidx) for the Android write probe | A wrapper over the `COLUMN_FLAGS` query we already have to run. A dependency for nothing. |
| `createDocument` + delete, to get an atomic Android replace | Changes the URI, so the persisted grant and every recents entry die. Worse than the problem. |

## Consequences

**Easier.** The whole decision layer is pure Dart and testable with no disk and
no channel — OPH-255 ships fully verified by `flutter test`, and OPH-256 becomes
three native implementations behind one already-proven interface. The UI
(OPH-251) cannot construct an illegal state.

**Harder.** macOS is the one place where correctness depends on a *build
configuration* that no test can see: `app-sandbox` is already on, so a missing
entitlement returns read-only rather than failing, which reads exactly like a
legitimately read-only file. Verification there is a device round with `shasum`
before and after, and OPH-256 carries a written fallback
(`ExternalHandleKind.sessionOnly`) for the case where ad-hoc-signed builds do
not honour app-scope bookmarks.

**Accepted risk, stated rather than discovered.** Saving to a Drive-backed
Android file re-reads up to 2 MB through a possibly-remote provider on every
save, because that provider reports neither size nor mtime. That is the price of
W5 being true instead of decorative.

**Follow-ups.** OPH-256 implements the three platforms; OPH-251 builds the W1–W6
interface. Live reload (§3.1) is explicitly out of scope here — `probe()`
returning a fresh stamp is the primitive it will need.
