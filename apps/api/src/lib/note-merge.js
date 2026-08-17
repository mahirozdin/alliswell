import { diff3Merge } from 'node-diff3';

/**
 * Three-way merge for markdown note bodies (OPH-268, ADR-0031 §8).
 *
 * Pure: text in, text or a refusal out. The server owns merging because
 * pub.dev has no three-way merge package (the Epic 25 survey) and two engines
 * in two languages would answer one question twice.
 *
 * Line level first, then a WORD-level pass inside each conflicted region —
 * the diff3 paper's own caveat is that its guarantees hold in "well-separated"
 * regions, and markdown paragraphs are single long lines, so two people
 * editing opposite ends of one paragraph look like a line conflict when
 * nothing actually overlaps. Refining by word is what makes that case merge
 * instead of interrupting somebody.
 *
 * What it never does: pick a side. A genuine overlap returns
 * `{ ok: false, reason: 'OVERLAP' }` and the caller takes the conflict path —
 * no fuzzy patching (the reason diff-match-patch is not here; Obsidian warns
 * its own fuzzy merge "may produce duplicates").
 */

/** CRLF/CR → LF. Two devices, two platforms, one line ending. */
export function normalizeText(value) {
  return String(value ?? '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');
}

/** Words plus the whitespace between them — jsdiff's `diffWords` granularity. */
function tokenizeWords(text) {
  return text.split(/(\s+)/).filter((token) => token !== '');
}

/** Runs diff3 over three token arrays; null when a region genuinely overlaps. */
function mergeTokens(ours, base, theirs) {
  const regions = diff3Merge(ours, base, theirs);
  const merged = [];
  for (const region of regions) {
    if (region.ok) {
      merged.push(...region.ok);
      continue;
    }
    return null;
  }
  return merged;
}

/**
 * @param {string} base the body both sides started from
 * @param {string} ours the body already on the server
 * @param {string} theirs the body arriving from the client
 * @returns {{ok: true, text: string, refined: boolean}|{ok: false, reason: 'OVERLAP'}}
 */
export function mergeMarkdown(base, ours, theirs) {
  const baseLines = normalizeText(base).split('\n');
  const ourLines = normalizeText(ours).split('\n');
  const theirLines = normalizeText(theirs).split('\n');

  const regions = diff3Merge(ourLines, baseLines, theirLines);
  const out = [];
  let refined = false;

  for (const region of regions) {
    if (region.ok) {
      out.push(...region.ok);
      continue;
    }
    // A line-level conflict. Before calling it one, look at the words: this is
    // the single-line-paragraph trap, and it is the common case in markdown.
    const { a, o, b } = region.conflict;
    const words = mergeTokens(
      tokenizeWords(a.join('\n')),
      tokenizeWords(o.join('\n')),
      tokenizeWords(b.join('\n')),
    );
    if (!words) return { ok: false, reason: 'OVERLAP' };
    refined = true;
    out.push(...words.join('').split('\n'));
  }

  return { ok: true, text: out.join('\n'), refined };
}
