# ADR-0013 — Local-first search with app-owned Turkish folding

- **Status:** Accepted
- **Date:** 2026-07-20
- **Related task:** OPH-167 (Epic 15, feedback round 8)

## Context

Feedback round 8 (Mahir, 2026-07-20): every content screen needs search — title
first, then tags, then full body text — **case-insensitive and Turkish-tolerant**
("cay" must find "çay", "isi" must find "ısı", "ULKU" must find "ülkü"), fast at
scale, with honest loading states. Home search must also cover connected-calendar
events.

The app is local-first (ADR-0008 lineage): every synced entity already lives in
the device's drift/SQLite replica, on all six platforms (native SQLite on
iOS/Android/macOS/Windows/Linux, sqlite3.wasm on web). So the real question is
not "which search API" but "how does SQLite match Turkish text correctly and
fast".

Research was verified empirically (SQLite 3.51 CLI, MySQL server probes, Unicode
DUCET 9.0.0 tables, FTS5 fold source) before this decision:

1. **SQLite `LIKE` folds ASCII only.** `'ç' LIKE 'Ç'` is FALSE; `upper('çay')` =
   `çAY`. Raw LIKE over original text can never satisfy the requirement.
   (https://www.sqlite.org/lang_expr.html)
2. **FTS5 `unicode61 remove_diacritics 2` folds ç/ğ/ş/ü/ö/â → c/g/s/u/o/a and
   İ → i, but ı (U+0131) NEVER folds to i** — dotless ı has no canonical
   decomposition and no case-fold entry, so `MATCH 'isi'` cannot find "ısı".
   Verified against the fts5 fold tables (`fts5_unicode2.c`, generated from
   CaseFolding.txt). (https://www.sqlite.org/fts5.html §4.3.1)
3. **MySQL `utf8mb4_0900_ai_ci` has the exact same blind spot:** ç=c, ü=u, İ=i
   all TRUE, but ı=i FALSE — DUCET 9.0.0 gives ı its own primary weight
   (`0131 → 1D36` vs `0069 → 1D32`). The Turkish tailoring
   `utf8mb4_tr_0900_ai_ci` is WORSE for folding (ç≠c, ü≠u — they are distinct
   Turkish alphabet letters). (https://www.unicode.org/Public/UCA/9.0.0/allkeys.txt)
4. **Measured scan costs** (100k rows × ~124-char folded text, desktop; phones
   ≈3–6× slower): infix `LIKE '%q%'` full scan ≈ 12–21 ms (→ ~50–120 ms on a
   phone; ~5–15 ms at 10k rows). FTS5 MATCH is 0.05–3 ms but only matches token
   prefixes, never infixes — a real cost for Turkish agglutinative suffixes.

Conclusion: **no engine folds Turkish correctly on its own. Folding must be
app-owned**, applied identically to stored text and to queries.

## Decision

1. **One fold function, app-owned, no dependencies.** `foldSearchText()` in
   Dart with a byte-identical JS mirror on the API:
   - map `İ → i`, `I → i`, `ı → i` FIRST (before lowercasing — U+0130's Unicode
     lowercase leaves a stray combining dot);
   - `toLowerCase()`;
   - decompose accents via an explicit const map covering Latin-1 Supplement +
     Latin Extended-A (U+00C0–U+017F: ç→c, ğ→g, ş→s, ö→o, ü→u, â→a, é→e, …)
     instead of a Unicode-normalization dependency — Dart has no built-in NFD
     and the repo's i18n philosophy is app-owned machinery (ADR-0009);
   - collapse whitespace runs; trim.
   **Parity is guarded by a shared fixture** (`fold_parity.json`: input →
   folded pairs) tested by both `flutter test` and Vitest — the OPH-045/156
   markdown-parity precedent.
2. **Folded shadow columns in the replica, LIKE + tier UNION for queries (v1).**
   Drift v6 adds `*_fold` TEXT columns: tasks (`title_fold`,
   `description_fold`), notes (`title_fold`, `body_fold` — from the delta's
   plain text), projects (`name_fold`, `description_fold`), tags (`name_fold`),
   external_events (`summary_fold`, `location_fold`). They are populated at the
   two write choke points — feature stores (local writes) and the sync applier
   (pulled rows) — and backfilled once in the v6 migration step. Search runs as
   a single SQL statement per screen: tier 0 = title/name LIKE, tier 1 = tag
   name LIKE (joined via task_tags), tier 2 = body/description LIKE, unioned,
   `MIN(tier)` per id, ordered by tier then the screen's natural sort.
   Multi-word queries AND their words (each word must match somewhere).
3. **Query semantics:** infix substring match (`%word%`), word-order-free.
   Debounce ~250 ms; queries run async off the UI thread; the progress row
   appears only past 150 ms (DESIGN §12 S4).
4. **Server stays secondary and honest.** The app never searches over REST.
   For API consumers, tasks gain `?q=` using the already-existing (unused)
   `ft_tasks_title_description` FULLTEXT index; notes `?q=` already exists.
   Both inherit `utf8mb4_0900_ai_ci` folding — good for ç/ü/ö/İ, **known ı/i
   gap documented here**: acceptable for the secondary path. Server-side fold
   columns are the documented upgrade if server search ever becomes primary.

## Alternatives considered

- **FTS5 external-content tables** (over folded text, bm25 column weights):
  10–100× faster matching and real relevance ranking, but (a) only
  token-prefix matching — loses infix hits inside Turkish suffix chains unless
  the trigram tokenizer is added (3-char minimum, another moving part); (b)
  needs `.drift` DDL + three sync triggers per table; (c) wasm parity is fine
  (FTS5 is compiled into drift's sqlite3.wasm) but the setup surface is much
  larger. **Rejected for v1; documented as the measured upgrade path** if
  corpora grow past ~100k rows or ranking quality demands bm25.
- **Custom Dart SQL function (`createFunction`) at query time** — no shadow
  columns, but on web it requires shipping a custom drift worker, and it runs
  the fold per row per query instead of once per write. Rejected.
- **Fold at query time in Dart (load all rows, filter in app)** — materializes
  every row on every keystroke; the SQL scan keeps misses inside SQLite's C
  loop. Rejected.
- **A Unicode-normalization package (unorm_dart) instead of the explicit map**
  — more universal for non-Latin scripts, but adds a dependency for a corpus
  that is overwhelmingly Latin-script; the explicit map is deterministic,
  dependency-free and fully covered by the parity fixture. Non-Latin scripts
  still match exactly (casefolded), they just don't de-accent. Revisit only
  with real demand.
- **Server-side search API as the primary path** — contradicts local-first
  (offline search would break), adds latency and load. Rejected.

## Consequences

- Search works offline, instantly, identically on all six platforms; the fold
  behavior is a product promise (BLUEPRINT §12.10) guarded by unit tests + the
  cross-stack parity fixture.
- Replica schema v6 adds fold columns + a one-time backfill; stores and the
  sync applier MUST route text writes through the fold helper — a new-code
  checklist item (missing it silently breaks search for that entity; the
  applier test asserts fold columns on every applied entity type).
- The ı/i gap remains on the server `?q=` path only, documented above.
- If FTS5 is adopted later, the fold columns feed it unchanged — the v1 work
  is not throwaway.
