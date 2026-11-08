# ADR-0067 — Quick add: a repeat needs a real frequency phrase

- **Status:** Accepted
- **Date:** 2026-11-08
- **Related task:** OPH-420 (issue #32)
- **Amends:** [ADR-0054](0054-offline-quick-add-grammar.md) decision 2 ("both languages, always")

## Context

Issue #32: quick-added tasks became recurring from ordinary words, and Home then skipped its date
picker (ADR-0054 #8) and started a series without a word. Three classes of false positive:

1. **A period read as a frequency.** "Bu ayda bir toplantı" ("a meeting this month") matched
   `ayda bir` and became monthly; the title lost words.
2. **English words inside Turkish.** ADR-0054 #2 keeps both languages active, so "daily
   toplantısı" (the daily-meeting document) or "mondays toplantısı" became a daily / weekly task.
3. **"pazarları"** is "Sundays" and also "the markets".

## Decision

1. **A determiner makes it a period.** `[N] günde/haftada/ayda/yılda bir` right after
   `bu, şu, o, gelecek, önümüzdeki, geçen, geçtiğimiz, sonraki, ilk, son, aynı, öteki, diğer` is
   not a repeat; after `her` it always is ("her ayda bir").
2. **Bare English frequency words count only in an English sentence.** `daily`, `weekly`,
   `monthly`, `yearly`, `annually` and plural weekdays (`mondays`, `on fridays`) schedule the task
   when the UI language is English, or else when the sentence shows no Turkish (no Turkish-only
   letter, no Turkish-only word from a closed list, no Turkish weekday or month) and the next word
   is not a Turkish compound head (`…sı/si/su/sü`, `…ları/leri`). `every …` is its own English
   construction and stays ungated; every other rule still reads both languages (ADR-0054 #2
   otherwise unchanged). The parser takes the UI language as `AwQuickParseOptions.language`.
3. **Sundays need a frame.** `pazarları` alone stays text; `her pazar` and `pazar günleri`
   repeat. The other weekday plurals (`cumaları`, `pazartesileri`) keep repeating, and
   `<weekday> günleri` is added for every day.
4. **Never silent.** When Home's quick add starts a series, its confirmation names the rule
   ("Added: spor · Oct 19, 9:00 AM · Repeats: Every week on Monday").

The fixture (`apps/app/test/fixtures/quick_parse_cases.json`) carries a negative case for each
class and the positives kept; cases may now set `options.language`.

## Alternatives considered

- **Drop English bare words entirely in a Turkish UI.** Loses "daily standup" for bilingual
  teams that type English task names; the evidence rule keeps it.
- **A confirmation dialog before every typed repeat.** More friction on the common, correct
  case; the chip, the named snackbar and its Undo already make it visible and reversible.

## Consequences

The parser now has one input that depends on the UI (language); headless capture passes it from
`quickParseOptions`. A future JS twin must read `options.language` from the fixture.
