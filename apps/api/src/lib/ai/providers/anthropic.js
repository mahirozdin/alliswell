import { aiFetch, AiProviderError } from '../http.js';
import { parseSseStream } from '../sse.js';

/**
 * Anthropic Messages API (OPH-216). Stream events: `message_start` carries
 * input tokens, `content_block_delta`/`text_delta` the text,
 * `message_delta` output tokens + stop reason, `message_stop` the end;
 * `ping` is noise and `error` is a throw. Constrained output goes through
 * structured outputs (`output_format: json_schema` + its beta header — kept
 * even if long since GA'd, harmless and explicit).
 */
const API_VERSION = '2023-06-01';
const STRUCTURED_OUTPUT_BETA = 'structured-outputs-2025-11-13';
// The Messages API REQUIRES max_tokens; this is the ceiling when the caller
// has no opinion.
const DEFAULT_MAX_TOKENS = 4096;

const headers = (apiKey, extra = {}) => ({
  'x-api-key': apiKey,
  'anthropic-version': API_VERSION,
  ...extra,
});

export default {
  name: 'anthropic',
  capabilities: () => ({ chat: true, extract: true, transcribe: false, liveModels: false }),

  async *chatStream({ baseUrl, apiKey, model, system, messages, maxTokens, signal }) {
    const res = await aiFetch(`${baseUrl}/v1/messages`, {
      headers: headers(apiKey),
      json: {
        model,
        max_tokens: maxTokens ?? DEFAULT_MAX_TOKENS,
        ...(system ? { system } : {}),
        messages,
        stream: true,
      },
      signal,
      stream: true,
    });

    let inputTokens = null;
    let outputTokens = null;
    let stopReason = null;
    for await (const event of parseSseStream(res.body)) {
      if (event.event === 'ping') continue;
      const data = JSON.parse(event.data);
      switch (event.event || data.type) {
        case 'message_start':
          inputTokens = data.message?.usage?.input_tokens ?? null;
          break;
        case 'content_block_delta':
          if (data.delta?.type === 'text_delta' && data.delta.text) {
            yield { type: 'text', text: data.delta.text };
          }
          break;
        case 'message_delta':
          outputTokens = data.usage?.output_tokens ?? outputTokens;
          stopReason = data.delta?.stop_reason ?? stopReason;
          break;
        case 'error':
          throw new AiProviderError('upstream_error', { body: data.error ?? data });
        default:
          break; // content_block_start/stop and friends carry nothing we need
      }
      if ((event.event || data.type) === 'message_stop') break;
    }
    if (inputTokens !== null || outputTokens !== null) {
      yield { type: 'usage', inputTokens, outputTokens };
    }
    yield { type: 'done', stopReason };
  },

  async extract({ baseUrl, apiKey, model, system, input, schema, schemaName, signal }) {
    const res = await aiFetch(`${baseUrl}/v1/messages`, {
      headers: headers(apiKey, { 'anthropic-beta': STRUCTURED_OUTPUT_BETA }),
      json: {
        model,
        max_tokens: DEFAULT_MAX_TOKENS,
        ...(system ? { system } : {}),
        messages: [{ role: 'user', content: input }],
        output_format: { type: 'json_schema', schema, name: schemaName },
      },
      signal,
    });
    const raw = res.content?.[0]?.text ?? '';
    const usage = {
      inputTokens: res.usage?.input_tokens ?? null,
      outputTokens: res.usage?.output_tokens ?? null,
    };
    try {
      return { json: JSON.parse(raw), usage };
    } catch {
      throw new AiProviderError('bad_json', { rawText: raw });
    }
  },

  async verify({ baseUrl, apiKey, signal }) {
    await aiFetch(`${baseUrl}/v1/models`, {
      method: 'GET',
      headers: headers(apiKey),
      signal,
      timeoutMs: 10000,
      maxAttempts: 1,
    });
    return { ok: true };
  },
};
