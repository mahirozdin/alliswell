import {
  aiFetch,
  AiProviderError,
  CHAT_HANDSHAKE_TIMEOUT_MS,
  EXTRACT_TIMEOUT_MS,
} from '../http.js';
import { parseJsonLines } from '../sse.js';

/**
 * Ollama /api/chat (OPH-216) — the self-host DNA provider. NDJSON, not SSE:
 * `{message:{content}, done:false}` lines, then a final `{done:true}` line
 * carrying `prompt_eval_count`/`eval_count`. Constrained output is `format`
 * with a FULL JSON Schema (grammar-enforced since Ollama 0.5). Keyless by
 * default; an optional key becomes a bearer for authed reverse proxies.
 * The only provider with live model listing (`/api/tags`) — an instance's
 * pulled models are genuinely instance-specific.
 */
const headers = (apiKey) => (apiKey ? { authorization: `Bearer ${apiKey}` } : {});

const withSystem = (system, messages) =>
  system ? [{ role: 'system', content: system }, ...messages] : messages;

export default {
  name: 'ollama',
  capabilities: () => ({ chat: true, extract: true, transcribe: false, liveModels: true }),

  async *chatStream({ baseUrl, apiKey, model, system, messages, maxTokens, signal }) {
    const res = await aiFetch(`${baseUrl}/api/chat`, {
      headers: headers(apiKey),
      json: {
        model,
        messages: withSystem(system, messages),
        stream: true,
        ...(maxTokens ? { options: { num_predict: maxTokens } } : {}),
      },
      signal,
      stream: true,
      // A cold local model can spend a while loading before the first byte.
      timeoutMs: CHAT_HANDSHAKE_TIMEOUT_MS,
    });

    let usage = null;
    let stopReason = null;
    for await (const line of parseJsonLines(res.body)) {
      if (line.error) throw new AiProviderError('upstream_error', { body: line });
      if (line.message?.content) yield { type: 'text', text: line.message.content };
      if (line.done) {
        usage = {
          inputTokens: line.prompt_eval_count ?? null,
          outputTokens: line.eval_count ?? null,
        };
        stopReason = line.done_reason ?? 'stop';
        break;
      }
    }
    if (usage) yield { type: 'usage', ...usage };
    yield { type: 'done', stopReason };
  },

  async extract({ baseUrl, apiKey, model, system, input, schema, signal }) {
    const res = await aiFetch(`${baseUrl}/api/chat`, {
      headers: headers(apiKey),
      json: {
        model,
        messages: withSystem(system, [{ role: 'user', content: input }]),
        format: schema,
        stream: false,
      },
      signal,
      // Non-streaming: headers arrive when the WHOLE generation is done.
      timeoutMs: EXTRACT_TIMEOUT_MS,
    });
    const raw = res.message?.content ?? '';
    const usage = {
      inputTokens: res.prompt_eval_count ?? null,
      outputTokens: res.eval_count ?? null,
    };
    try {
      return { json: JSON.parse(raw), usage };
    } catch {
      throw new AiProviderError('bad_json', { rawText: raw });
    }
  },

  async verify({ baseUrl, apiKey, signal }) {
    await aiFetch(`${baseUrl}/api/tags`, {
      method: 'GET',
      headers: headers(apiKey),
      signal,
      timeoutMs: 10000,
      maxAttempts: 1,
    });
    return { ok: true };
  },

  async listModels({ baseUrl, apiKey, signal }) {
    const res = await aiFetch(`${baseUrl}/api/tags`, {
      method: 'GET',
      headers: headers(apiKey),
      signal,
      timeoutMs: 10000,
      maxAttempts: 1,
    });
    return (res?.models ?? []).map((m) => ({ id: m.name }));
  },
};
