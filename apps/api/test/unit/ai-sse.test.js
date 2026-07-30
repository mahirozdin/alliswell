import { describe, it, expect } from 'vitest';
import { parseSseStream, parseJsonLines } from '../../src/lib/ai/sse.js';

/** OPH-216 — the hand-written parsers, spec corner by spec corner. */

const encoder = new TextEncoder();

function streamOf(...chunks) {
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(typeof chunk === 'string' ? encoder.encode(chunk) : chunk);
      }
      controller.close();
    },
  });
}

async function collect(iterable) {
  const out = [];
  for await (const item of iterable) out.push(item);
  return out;
}

describe('parseSseStream', () => {
  it('parses events, joins multi-line data with \\n', async () => {
    const events = await collect(
      parseSseStream(streamOf('data: line one\ndata: line two\n\n', 'data: solo\n\n')),
    );
    expect(events).toEqual([
      { event: 'message', data: 'line one\nline two', id: undefined },
      { event: 'message', data: 'solo', id: undefined },
    ]);
  });

  it('skips comment lines (heartbeats) and unknown fields', async () => {
    const events = await collect(
      parseSseStream(streamOf(': hb\n\n: another\ndata: x\nretry: 100\nfoo: bar\n\n')),
    );
    expect(events).toEqual([{ event: 'message', data: 'x', id: undefined }]);
  });

  it('tolerates CRLF line endings', async () => {
    const events = await collect(parseSseStream(streamOf('event: text\r\ndata: {"a":1}\r\n\r\n')));
    expect(events).toEqual([{ event: 'text', data: '{"a":1}', id: undefined }]);
  });

  it('carries event names and ids, strips ONE leading space', async () => {
    const events = await collect(
      parseSseStream(streamOf('event: done\nid: 7\ndata:  two spaces\n\n')),
    );
    // First space after the colon is syntax; the second is data.
    expect(events).toEqual([{ event: 'done', data: ' two spaces', id: '7' }]);
  });

  it('discards an incomplete event at EOF (spec behavior)', async () => {
    const events = await collect(parseSseStream(streamOf('data: complete\n\ndata: half')));
    expect(events).toEqual([{ event: 'message', data: 'complete', id: undefined }]);
  });

  it('reassembles a multi-byte character split across chunks', async () => {
    const bytes = encoder.encode('data: baş\n\n');
    // Split inside 'ş' (a 2-byte UTF-8 sequence near the end).
    const cut = bytes.length - 4;
    const events = await collect(
      parseSseStream(streamOf(bytes.subarray(0, cut), bytes.subarray(cut))),
    );
    expect(events[0].data).toBe('baş');
  });

  it('cancels the upstream reader when the consumer breaks', async () => {
    let cancelled = false;
    const endless = new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode('data: first\n\n'));
        // never closes
      },
      cancel() {
        cancelled = true;
      },
    });
    for await (const event of parseSseStream(endless)) {
      expect(event.data).toBe('first');
      break;
    }
    expect(cancelled).toBe(true);
  });
});

describe('parseJsonLines', () => {
  it('buffers partial lines across chunks and parses the tail without newline', async () => {
    const lines = await collect(parseJsonLines(streamOf('{"a"', ':1}\n{"b":2}\n', '{"c":3}')));
    expect(lines).toEqual([{ a: 1 }, { b: 2 }, { c: 3 }]);
  });

  it('skips blank lines', async () => {
    const lines = await collect(parseJsonLines(streamOf('\n\n{"ok":true}\n\n')));
    expect(lines).toEqual([{ ok: true }]);
  });

  it('cancels the upstream reader when the consumer breaks', async () => {
    let cancelled = false;
    const endless = new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode('{"first":true}\n'));
      },
      cancel() {
        cancelled = true;
      },
    });
    for await (const line of parseJsonLines(endless)) {
      expect(line).toEqual({ first: true });
      break;
    }
    expect(cancelled).toBe(true);
  });
});
