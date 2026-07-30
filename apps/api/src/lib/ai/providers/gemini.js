import { aiFetch, AiProviderError } from '../http.js';
import { parseSseStream } from '../sse.js';

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
  capabilities: () => ({ chat: true, extract: true, transcribe: false, liveModels: false }),

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
