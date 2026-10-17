# ADR-0054 — Offline quick-add grammar (Turkish and English)

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-373

## Context

Natural-language entry is a core expectation of a task app, and a feature people resent paying
Todoist for (2026-10-16 research). Until v1.17.0 the quick-add bars sent plain text. Dates could
only come from the optional ✨ AI rider (OPH-222), which needs a configured provider, and
docs/COMPARISON.md recorded that as a weakness. The research wording: "Yarın 9'da kira #ev" must
become a dated, tagged task offline, without any key.

Three bars exist (Home, Inbox, a project's Tasks tab), and OPH-376 (Siri and Android capture)
will need the same reading of a sentence without any UI.

## Decision

1. **Where it lives.** A pure Dart parser in `apps/app/lib/src/core/quick_parse.dart`, next to
   the fold and the recurrence engine: no Flutter, no i18n, an injected `now`, deterministic.
   `features/tasks/data/quick_add_apply.dart` turns a parse into a task (tags resolved, the
   series started) from a `ref.read` with no BuildContext. OPH-376 calls both headless.
2. **Both languages, always.** Turkish and English words are active whatever the UI language,
   matched on the ADR-0013 fold, so ASCII-typed Turkish ("yarin", "carsamba") works too.
3. **A plain date is the deadline.** An unmarked date phrase fills `dueAt`; a day without a time
   gets the default task time (23:59 factory) and the round-14 auto-reminder. Evidence: the
   Todoist/TickTick importer maps a date to `dueAt`, the AI rider writes `dueAt`, and Home's
   deadline ask (DESIGN §26 C3) writes `dueAt`. Only `dueAt` can hold "9'da"; "when" is a day
   (ADR-0053).
   - Explicit deadline: TR `son`, `son gün`, `bitiş` before the date, or `<date>'(y)a kadar`
     ("cumaya kadar"); EN `due`, `by`, `deadline` before it.
   - "When" (`startAt`, local midnight): TR `başla` / `başlangıç` right before or right after
     the date; EN `start` / `starts` / `starting` before it. A time next to a when-phrase is
     not taken (a when-day has no time).
   - A weekday deadline next to a later When day counts from that day: "başla pazartesi son
     cuma" is the Friday after that Monday, never a deadline before the start.
4. **Marks.** `#tag` (the OPH-165 convention; fold-matched to an existing tag, else created).
   `+Project`, matched only against EXISTING projects (longest exact multi-word name, then a
   unique prefix); an unknown name stays in the title and nothing is auto-created. `@` was not
   used because Todoist's `@` means label and our importer already turns `@labels` into tags.
   Priority follows the importer's Todoist mapping: `p1`/`!1` = high, `p2` = medium, `p3` = low,
   `p4` = none; `!acil`/`!urgent`, `!yüksek`/`!high`, `!orta`/`!medium`, `!düşük`/`!low` name
   the levels.
5. **Recurrence** maps onto the ADR-0020 rule (daily/weekly/monthly/yearly, interval, weekday
   lists, month day 1..31 or -1) and is validated by `awValidateRepeatRule`. The deadline is the
   rule's first occurrence strictly after now (anchored on a typed date, else today), so "her
   pazartesi 9'da" typed on a Monday at 10:00 is not born overdue. The series adopts the new
   task with the create sheet's template fields.
6. **Collisions are designed out, then undoable.** A bare number is never a time or a date;
   month names count only next to a day number ("may I"); `sat`/`sun` only after a keyword;
   Turkish suffix lists are closed (`pazardan`, `Yarınki` do not match); `3.5` and `1/2` need a
   two-digit part. Every recognition is a chip with ✕; a dismissed phrase's words stay text
   and may not be taken by another rule.
7. **Time and week.** Device-local wall time, like every date in the app; all day arithmetic is
   `DateTime(y, m, d + n)`. Weeks start on Monday (no setting exists; the month grid and the
   engine are Monday-first) — the parser takes `weekStart` for later. `5/11` is month-first only
   under the US date format preference or a "system" format with an English UI.
8. **Home skips its deadline ask** when the text already gives a deadline, a when-day or a
   repeat; the text wins over the selected calendar day (DESIGN §26 C3 amended, §39 Q4). In the
   Inbox and on a project tab a parsed deadline applies the same quick-add defaults (C4); without
   one they behave as before.
9. **Not parsed here:** duration ("30 dk") and repeat ends ("5 kez", "until") — the dialogs still
   edit them.
10. **The ✨ AI rider is unchanged.** It still receives the raw text; the offline parse is not
    applied on that path.
11. **No dependency added.** The parser is about 1,300 lines of plain Dart.
12. **Rule 12.** No MCP or REST change: every field the parser fills (`dueAt`, `startAt`,
    `tagIds`, `projectId`, `priority`, a series) is already on MCP `create_task` and the REST
    surface, and MCP clients are LLMs that structure text themselves. The parser is a client
    input affordance, not a capability.

## The contract

`apps/app/test/fixtures/quick_parse_cases.json` (200+ cases with a fixed Friday "now") is the
grammar's contract. If capture ever has to parse on the server, a JS twin must pass this file
unchanged — the `fold_parity.json` arrangement (LESSONS docs-gates). The in-app help sheet
(`quick_add_help_sheet.dart`) and DESIGN §39 summarize it; change the four together.

## Alternatives considered

- **A date-parsing package** (chrono-style). Rejected: none handles Turkish suffixes and
  assimilation ("14'te", "cumaya", "kasım'da"), and a dependency would still need our rules on
  top (due vs when, ADR-0020 rules, the fold).
- **Make the plain date the "when" day** (Things' model). Rejected: every existing date path
  writes the deadline, and "9'da" needs a field that holds a time.
- **Parse only in the UI language.** Rejected: bilingual users mix them, and a Turkish UI user
  pasting "tomorrow 3pm" should not get a dateless task.
- **Run the AI parse by default.** Rejected by the brief: the model stays an optional extra.

## Consequences

- Ordinary titles can be misread ("pazar" as Sunday, "weekend"). The chips make that visible
  before saving and ✕ undoes it; the negative group in the fixture pins the known traps.
- The highlight paints the field only when nothing is composing (IME safety), so the colouring
  appears once a word is committed. Real keyboards are queued in DEVICE-CHECKS.
- Occurrences after the first carry no reminder, like series created from the sheet today.
