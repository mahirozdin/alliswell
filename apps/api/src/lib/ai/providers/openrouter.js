import { createOpenAiDialectAdapter } from './openai.js';

/**
 * OpenRouter = the OpenAI dialect at another base URL (OPH-216). The courtesy
 * headers are OpenRouter's app-attribution convention; `max_tokens` because it
 * fans out to vendors that never learned `max_completion_tokens`; and
 * `/v1/auth/key` verifies the key itself without spending a token.
 */
export default createOpenAiDialectAdapter({
  name: 'openrouter',
  maxTokensParam: 'max_tokens',
  verifyPath: '/v1/auth/key',
  extraHeaders: {
    'http-referer': 'https://github.com/mahirozdin/alliswell',
    'x-title': 'AllisWell',
  },
});
