/**
 * The hand-written stream parsers (OPH-216, ADR-0019 §2: "the ~80-line SSE
 * parser is ours" — no eventsource dependency).
 *
 * `parseSseStream` speaks the SSE wire format the three cloud dialects use:
 * `data:`/`event:`/`id:` fields, `:` comment lines, multi-line data joined
 * with '\n', a blank line dispatching the event, one leading space stripped
 * after the colon, \r\n tolerated. An incomplete event at EOF is discarded
 * (spec behavior). `[DONE]` is NOT this layer's business — the OpenAI dialect
 * checks its own sentinel.
 *
 * `parseJsonLines` speaks Ollama's NDJSON: one JSON object per line.
 *
 * Both decode with a streaming TextDecoder so a multi-byte character split
 * across chunk boundaries ('ş' arriving half-and-half) reassembles correctly,
 * and both cancel the upstream reader when the consumer stops iterating —
 * that is what makes `break`/`return` on the consumer side abort the socket.
 */

/** @param {ReadableStream<Uint8Array>} body */
export async function* parseSseStream(body) {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  let event = { event: 'message', data: [] };

  const flush = () => {
    const finished = event;
    event = { event: 'message', data: [] };
    if (finished.data.length === 0) return null;
    return { event: finished.event, data: finished.data.join('\n'), id: finished.id };
  };

  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      let newline;
      while ((newline = buffer.indexOf('\n')) !== -1) {
        let line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        if (line.endsWith('\r')) line = line.slice(0, -1);

        if (line === '') {
          const finished = flush();
          if (finished) yield finished;
          continue;
        }
        if (line.startsWith(':')) continue; // comment (heartbeats)

        const colon = line.indexOf(':');
        const field = colon === -1 ? line : line.slice(0, colon);
        let value2 = colon === -1 ? '' : line.slice(colon + 1);
        if (value2.startsWith(' ')) value2 = value2.slice(1);

        if (field === 'data') event.data.push(value2);
        else if (field === 'event') event.event = value2;
        else if (field === 'id') event.id = value2;
        // 'retry' and unknown fields are ignored.
      }
    }
  } finally {
    reader.cancel().catch(() => {});
  }
}

/** @param {ReadableStream<Uint8Array>} body */
export async function* parseJsonLines(body) {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let newline;
      while ((newline = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (line) yield JSON.parse(line);
      }
    }
    const rest = buffer.trim();
    if (rest) yield JSON.parse(rest);
  } finally {
    reader.cancel().catch(() => {});
  }
}
