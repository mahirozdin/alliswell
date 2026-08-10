# ADR-0023 — On-device STT and share-intent: two platform-channel dependencies + a second iOS extension

- **Status:** Accepted
- **Date:** 2026-07-30
- **Related task:** OPH-223 (voice) and OPH-225 (share), Epic 20
- **Related:** [ADR-0019](0019-ai-provider-architecture.md) (the AI architecture),
  [ADR-0010](0010-home-screen-widgets-architecture.md) (the pbxproj-deviation
  precedent this follows), [ADR-0016](0016-in-app-url-routing-and-widget-actions.md)
  (the deep-link replay pattern the share payload reuses), [AI.md](../AI.md) §5–6,
  DESIGN §24.

## Context

Voice capture and the OS share sheet need platform surfaces Flutter core does
not expose. The owner's primary UX ("hold to talk, share any text into the
app") depends on both. The repo's standing policy is minimal, seam-wrapped
dependencies (ADR-0006/0019): a plugin is allowed, but only behind an
abstract seam so the rest of the app — and every test — never touches it.

## Decision

1. **`speech_to_text` for on-device STT** (iOS SFSpeechRecognizer / iOS 26
   SpeechAnalyzer; Android SpeechRecognizer): free, offline-capable, live
   partials, Turkish supported, privacy-clean (AI.md §5). Used ONLY behind
   `SttController` (`features/ai/data/stt.dart`); a `FakeSttController` backs
   every test. v1 has no server STT (parked v1.5). On-device availability
   varies by device, so Settings shows the real `locales()` result and
   whether on-device recognition is active — an honest status, never a claim.
2. **`receive_sharing_intent` for the share target** (OPH-225): Android
   `ACTION_SEND` for `text/plain`/`text/html`; on iOS a **Share Extension**
   target. Used behind `ShareIntentSource` (`features/ai/data/share_intent.dart`).
3. **A second iOS app-extension target (`AllisWellShare`)** — the second
   sanctioned pbxproj deviation after ADR-0010's widget extension. The
   extension does **no network and no AI work** (extensions have hard
   memory/time ceilings, AI.md §6): it writes the shared payload to the App
   Group and opens the host app, which does the extraction.
   > **Amended by [ADR-0029](0029-share-extension-notifies-instead-of-redirecting.md)
   > (2026-08-10):** the extension **notifies** instead of opening the host app —
   > an appex cannot foreground its host on iOS 18+, measured — and the app
   > drains the App Group on launch and resume. Everything else in this item,
   > including "no network and no AI work", stands as written.
   Wiring is a
   committed, idempotent `ios/scripts/wire_share_extension.rb` (the
   `wire_alarmkit.rb` xcodeproj-gem pattern) so the pbxproj/entitlements diffs
   read as intentional. The App Group reuses `group.com.alliswell.alliswell`
   (already declared for widgets) — no new group.
4. **The gesture machine and the STT/share seams are pure and testable
   off-device.** `ai_ptt_machine.dart` is a pure state machine (no timers, no
   platform); the FAB widget owns the 250 ms hold timer and the plugin owns
   the 2 s VAD. So the hold-to-lock rule, the swipe-to-cancel, and the
   permission-denied → text-mode fallback are all unit/widget tested; only the
   real microphone and the real share sheet need a device tour (queued in
   STATE).

## Alternatives considered

- **Hand-rolled platform channels** for STT and shares — two large native
  surfaces reimplemented for zero product difference; the plugins are exactly
  the seam-wrappable kind ADR-0019 sanctions.
- **Server-side STT** (OpenAI/Gemini audio) — cost + a privacy inversion
  (audio would leave the device); parked as a v1.5 accuracy toggle. The seam
  is provider-independent by necessity (Claude has no audio input).
- **A URL/App-Links relay for shares instead of an extension** — iOS requires
  a Share Extension to appear in the share sheet at all; there is no
  URL-only path.

## Consequences

- Two new "platform-channel plugin" dependency-category entries; both stay
  behind seams, so `flutter test` never needs a platform channel.
- Microphone + speech-recognition permission strings (iOS two-part) and an
  Android `RECORD_AUDIO` permission; store-form disclosures updated (OPH-227).
- The committed pbxproj now carries two scripted extension targets; the
  `wire_*.rb` scripts are the source of truth for that surgery.
- Real-device verification (Turkish utterance → correct card; the OS share
  sheet, cold and warm) is queued in STATE's device tour — external to the
  code DoD.
