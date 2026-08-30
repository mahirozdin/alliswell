/**
 * ONE shape for a diarized transcript, whatever produced it.
 *
 * ── Why this file exists ──────────────────────────────────────────────────
 *
 * Speech providers disagree about almost everything in their output. One
 * returns `utterances` with `speaker: "A"` and millisecond `start`/`end`;
 * another returns `results.channels[].alternatives[].words[]` where the
 * speaker is an integer on every WORD and utterances have to be assembled;
 * a third returns whatever a language model was asked to return, in seconds,
 * as JSON inside a text part. Three vocabularies for one fact.
 *
 * A UI that reads any of those directly is a UI that must be rewritten to add
 * a provider — and worse, one whose bugs are per-provider. So nothing above
 * this line ever sees a provider's own shape: an adapter's job ends when it
 * hands back segments in the shape below, and this module is where that shape
 * is defined and CHECKED.
 *
 * ── The shape ─────────────────────────────────────────────────────────────
 *
 *   { segments: [{ speaker, startMs, endMs, text }], speakers: [id…],
 *     durationMs, language }
 *
 * Decisions inside it, each with a reason:
 *
 * • **Milliseconds, integers.** Providers variously send seconds as floats and
 *   milliseconds as ints. Floats in a timeline are how "0.1 + 0.2" bugs reach
 *   a seek bar; one unit, one type, converted once, at the edge.
 * • **`speaker` is an opaque STRING, not an index.** "A"/"B" and 0/1 both
 *   arrive, and a later screen lets somebody name a speaker (EE-115). A
 *   string that started life as "0" survives being renamed; an integer index
 *   invites arithmetic that means nothing.
 * • **`speakers` is derived, not trusted.** It is the distinct speakers that
 *   actually appear in `segments`, computed here. A provider's own count can
 *   disagree with its own output, and the list a UI iterates must be the one
 *   the rows can be grouped by.
 * • **`text` is trimmed and never empty.** An empty segment is a row that
 *   renders as a gap somebody will report as a bug.
 * • **No confidence field.** Two of the three report it, in different scales,
 *   and nothing in the product reads it. A field carried by two providers and
 *   read by none is the field that makes the schema look richer than it is.
 */

export class TranscriptShapeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TranscriptShapeError';
    this.code = 'TRANSCRIPT_SHAPE';
  }
}

const isFiniteNumber = (value) => typeof value === 'number' && Number.isFinite(value);

/** Seconds (float, as most providers report) → integer milliseconds. */
export const secondsToMs = (seconds) => Math.round(seconds * 1000);

/**
 * Validates and canonicalises what an adapter produced.
 *
 * Adapters call this on their way out, so a provider whose output drifts is
 * caught at the boundary rather than three screens later. It THROWS rather
 * than repairing: a transcript with a negative span or a segment that ends
 * before it starts is not a display problem to paper over, it is a parsing
 * bug in the adapter that produced it.
 *
 * The one thing it does repair is ORDER — segments are sorted by start time.
 * Providers that assemble utterances from words can emit them out of order,
 * and every consumer wants them in time order, so sorting once here beats
 * every caller remembering to.
 */
export function normalizeTranscript({ segments, durationMs = null, language = null }) {
  if (!Array.isArray(segments)) {
    throw new TranscriptShapeError('transcript: segments must be an array');
  }

  const clean = segments.map((segment, index) => {
    const where = `segment ${index}`;
    const speaker = segment?.speaker;
    if (typeof speaker !== 'string' || speaker.length === 0) {
      throw new TranscriptShapeError(`${where}: speaker must be a non-empty string`);
    }
    if (!isFiniteNumber(segment.startMs) || !isFiniteNumber(segment.endMs)) {
      throw new TranscriptShapeError(`${where}: startMs and endMs must be finite numbers`);
    }
    if (segment.startMs < 0 || segment.endMs < segment.startMs) {
      throw new TranscriptShapeError(
        `${where}: span must be non-negative and end at or after it starts`,
      );
    }
    const text = typeof segment.text === 'string' ? segment.text.trim() : '';
    if (text.length === 0) {
      throw new TranscriptShapeError(`${where}: text must be a non-empty string`);
    }
    return {
      speaker,
      startMs: Math.round(segment.startMs),
      endMs: Math.round(segment.endMs),
      text,
    };
  });

  clean.sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);

  if (durationMs !== null && (!isFiniteNumber(durationMs) || durationMs < 0)) {
    throw new TranscriptShapeError('transcript: durationMs must be a non-negative number');
  }

  return {
    segments: clean,
    // Derived on purpose — see the header.
    speakers: [...new Set(clean.map((s) => s.speaker))],
    // A provider that did not report a duration still has one: the end of the
    // last thing anybody said. Rounding up to that is honest and lets the
    // minute meter (EE-117) work the same way for every provider.
    durationMs: durationMs === null ? (clean.at(-1)?.endMs ?? 0) : Math.round(durationMs),
    language: typeof language === 'string' && language.length > 0 ? language : null,
  };
}

/**
 * Words carrying a speaker each → utterances.
 *
 * Two of the three providers report speech word-by-word and leave the grouping
 * to the caller, so the grouping lives here once rather than in each adapter.
 * A new utterance starts when the speaker changes — and ONLY then. Splitting
 * on a long pause was considered and left out: a pause threshold is a display
 * preference, and baking one in would make two adapters that read the same
 * audio disagree about how many segments there are.
 *
 * @param {{speaker: string, startMs: number, endMs: number, text: string}[]} words
 */
export function groupWordsBySpeaker(words) {
  const out = [];
  for (const word of words) {
    const last = out.at(-1);
    if (last && last.speaker === word.speaker) {
      last.endMs = word.endMs;
      last.text += ` ${word.text}`;
    } else {
      out.push({ ...word });
    }
  }
  return out;
}
