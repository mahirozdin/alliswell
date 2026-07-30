import { aiFetch, AiProviderError } from '../http.js';
import { parseSseStream } from '../sse.js';

/**
 * The OpenAI chat-completions dialect (OPH-216) — deliberately a FACTORY,
 * because OpenRouter speaks the same wire format: one implementation, two
 * providers. `/v1/chat/completions` (not `/v1/responses`) is the cross-vendor
 * lingua franca that makes the sharing possible (decision recorded in TASKS).
 *
 * Schema shaping is NOT this layer's job: `extract()` receives the already
 * provider-transformed schema (lib/ai/schema.js providerSchema) and passes it
 * through verbatim. Adapters stay dumb pipes.
 */
export function createOpenAiDialectAdapter({
  name,
  chatPath = '/v1/chat/completions',
  verifyPath = '/v1/models',
  maxTokensParam = 'max_completion_tokens',
  extraHeaders = {},
}) {
  const headers = (apiKey) => ({ authorization: `Bearer ${apiKey}`, ...extraHeaders });

  const withSystem = (system, messages) =>
    system ? [{ role: 'system', content: system }, ...messages] : messages;

  return {
    name,
    capabilities: () => ({ chat: true, extract: true, transcribe: false, liveModels: false }),

    async *chatStream({ baseUrl, apiKey, model, system, messages, maxTokens, signal }) {
      const res = await aiFetch(`${baseUrl}${chatPath}`, {
        headers: headers(apiKey),
        json: {
          model,
          messages: withSystem(system, messages),
          stream: true,
          stream_options: { include_usage: true },
          ...(maxTokens ? { [maxTokensParam]: maxTokens } : {}),
        },
        signal,
        stream: true,
      });

      let usage = null;
      let stopReason = null;
      for await (const event of parseSseStream(res.body)) {
        if (event.data === '[DONE]') break;
        const chunk = JSON.parse(event.data);
        if (chunk.error) throw new AiProviderError('upstream_error', { body: chunk.error });
        const choice = chunk.choices?.[0];
        if (choice?.delta?.content) yield { type: 'text', text: choice.delta.content };
        if (choice?.finish_reason) stopReason = choice.finish_reason;
        if (chunk.usage) {
          usage = {
            inputTokens: chunk.usage.prompt_tokens ?? null,
            outputTokens: chunk.usage.completion_tokens ?? null,
          };
        }
      }
      if (usage) yield { type: 'usage', ...usage };
      yield { type: 'done', stopReason };
    },

    async extract({ baseUrl, apiKey, model, system, input, schema, schemaName, signal }) {
      const res = await aiFetch(`${baseUrl}${chatPath}`, {
        headers: headers(apiKey),
        json: {
          model,
          messages: withSystem(system, [{ role: 'user', content: input }]),
          response_format: {
            type: 'json_schema',
            json_schema: { name: schemaName, strict: true, schema },
          },
        },
        signal,
      });
      const raw = res.choices?.[0]?.message?.content ?? '';
      const usage = {
        inputTokens: res.usage?.prompt_tokens ?? null,
        outputTokens: res.usage?.completion_tokens ?? null,
      };
      try {
        return { json: JSON.parse(raw), usage };
      } catch {
        throw new AiProviderError('bad_json', { rawText: raw });
      }
    },

    async verify({ baseUrl, apiKey, signal }) {
      await aiFetch(`${baseUrl}${verifyPath}`, {
        method: 'GET',
        headers: headers(apiKey),
        signal,
        timeoutMs: 10000,
        maxAttempts: 1,
      });
      return { ok: true };
    },
  };
}

export default createOpenAiDialectAdapter({ name: 'openai' });
