import {
  aiFetch,
  AiProviderError,
  CHAT_HANDSHAKE_TIMEOUT_MS,
  EXTRACT_TIMEOUT_MS,
  TRANSCRIBE_TIMEOUT_MS,
} from '../http.js';
import { parseSseStream } from '../sse.js';
import { normalizeTranscript, secondsToMs } from '../transcript.js';

/**
 * Diarization here is a REQUEST, not a feature (AI-EE.md §2). The schema is
 * what turns a request into something checkable: the model is constrained to
 * emit exactly these fields, and `normalizeTranscript` refuses the result if
 * it drifts anyway. Without both halves this adapter would return prose
 * shaped like a transcript on a good day.
 */
const TRANSCRIPT_SCHEMA = {
  type: 'object',
  properties: {
    segments: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          speaker: { type: 'string' },
          start: { type: 'number' },
          end: { type: 'number' },
          text: { type: 'string' },
        },
        required: ['speaker', 'start', 'end', 'text'],
      },
    },
  },
  required: ['segments'],
};

const TRANSCRIBE_PROMPT =
  'Transcribe this recording verbatim in its original language. Split it into ' +
  'segments, one per continuous stretch of a single speaker. Label speakers ' +
  '"Speaker 1", "Speaker 2" and so on, consistently across the whole ' +
  'recording. start and end are seconds from the beginning of the audio.';

/**
 * Gemini generateContent dialect (OPH-216). The API key travels in the
 * `x-goog-api-key` HEADER, never `?key=` — secrets must not reach URLs,
 * proxies, or logs (the fake asserts this). Streaming is
 * `:streamGenerateContent?alt=sse`; constrained output is `responseSchema`
 * (the caller hands us the Gemini-shaped variant).
 */
const headers = (apiKey) => ({ 'x-goog-api-key': apiKey });

const toContents = (messages) =>
  messages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

export default {
  name: 'gemini',
  // `transcribe` without `diarize`: this model can turn audio into words,
  // but telling speakers apart is PROMPTED behaviour here, not a contract
  // the provider keeps. Saying so in the capability is what lets a caller
  // choose a provider on the guarantee rather than on the feature list.
  capabilities: () => ({
    chat: true,
    extract: true,
    transcribe: true,
    diarize: false,
    // One synchronous generation, no job id: an attempt that dies has nothing
    // to come back to, so a caller that retries is starting over.
    resumable: false,
    liveModels: false,
  }),

  async *chatStream({ baseUrl, apiKey, model, system, messages, maxTokens, signal }) {
    const res = await aiFetch(
      `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`,
      {
        headers: headers(apiKey),
        json: {
          contents: toContents(messages),
          ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
          ...(maxTokens ? { generationConfig: { maxOutputTokens: maxTokens } } : {}),
        },
        signal,
        stream: true,
        timeoutMs: CHAT_HANDSHAKE_TIMEOUT_MS,
      },
    );

    let usage = null;
    let stopReason = null;
    for await (const event of parseSseStream(res.body)) {
      const chunk = JSON.parse(event.data);
      if (chunk.error) throw new AiProviderError('upstream_error', { body: chunk.error });
      const candidate = chunk.candidates?.[0];
      for (const part of candidate?.content?.parts ?? []) {
        if (part.text) yield { type: 'text', text: part.text };
      }
      if (candidate?.finishReason) stopReason = candidate.finishReason;
      if (chunk.usageMetadata) {
        usage = {
          inputTokens: chunk.usageMetadata.promptTokenCount ?? null,
          outputTokens: chunk.usageMetadata.candidatesTokenCount ?? null,
        };
      }
    }
    if (usage) yield { type: 'usage', ...usage };
    yield { type: 'done', stopReason };
  },

  async extract({ baseUrl, apiKey, model, system, input, schema, signal }) {
    const res = await aiFetch(
      `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        headers: headers(apiKey),
        json: {
          contents: [{ role: 'user', parts: [{ text: input }] }],
          ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
          generationConfig: { responseMimeType: 'application/json', responseSchema: schema },
        },
        signal,
        // Non-streaming: headers arrive when the WHOLE generation is done.
        timeoutMs: EXTRACT_TIMEOUT_MS,
      },
    );
    const raw = res.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    const usage = {
      inputTokens: res.usageMetadata?.promptTokenCount ?? null,
      outputTokens: res.usageMetadata?.candidatesTokenCount ?? null,
    };
    try {
      return { json: JSON.parse(raw), usage };
    } catch {
      throw new AiProviderError('bad_json', { rawText: raw });
    }
  },

  /**
   * Audio → segments. `audio` is either `{ uri, mimeType }` (a file already
   * uploaded to the provider — the only workable form past 20 MB, which is
   * most meetings) or `{ data, mimeType }` with base64 bytes for short ones.
   *
   * The timeout is its own constant and a large one: like `extract`, this is a
   * non-streaming call whose headers arrive only when the whole generation is
   * finished, and here the generation is an hour of speech.
   */
  async transcribe({ baseUrl, apiKey, model, audio, languageHint = null, signal }) {
    const part = audio?.uri
      ? { file_data: { file_uri: audio.uri, mime_type: audio.mimeType } }
      : { inline_data: { mime_type: audio?.mimeType, data: audio?.data } };
    const prompt = languageHint
      ? `${TRANSCRIBE_PROMPT} The recording is in ${languageHint}.`
      : TRANSCRIBE_PROMPT;

    const res = await aiFetch(
      `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        headers: headers(apiKey),
        json: {
          contents: [{ role: 'user', parts: [{ text: prompt }, part] }],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: TRANSCRIPT_SCHEMA,
          },
        },
        signal,
        timeoutMs: TRANSCRIBE_TIMEOUT_MS,
      },
    );

    const raw = res.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new AiProviderError('bad_json', { rawText: raw });
    }

    return {
      transcript: normalizeTranscript({
        segments: (parsed.segments ?? []).map((s) => ({
          speaker: String(s.speaker),
          startMs: secondsToMs(s.start),
          endMs: secondsToMs(s.end),
          text: s.text,
        })),
        language: languageHint,
      }),
      // Audio is billed as input tokens here, not minutes — the meter records
      // what the provider actually charges for.
      usage: {
        inputTokens: res.usageMetadata?.promptTokenCount ?? null,
        outputTokens: res.usageMetadata?.candidatesTokenCount ?? null,
      },
    };
  },

  async verify({ baseUrl, apiKey, signal }) {
    await aiFetch(`${baseUrl}/v1beta/models`, {
      method: 'GET',
      headers: headers(apiKey),
      signal,
      timeoutMs: 10000,
      maxAttempts: 1,
    });
    return { ok: true };
  },
};
