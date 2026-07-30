import anthropic from './anthropic.js';
import openai from './openai.js';
import gemini from './gemini.js';
import openrouter from './openrouter.js';
import ollama from './ollama.js';

/**
 * The provider registry (OPH-216, ADR-0019): five thin fetch adapters behind
 * one contract — `capabilities()`, `chatStream()` (an async generator of
 * normalized `{type: 'text'|'usage'|'done'}` events; failures THROW
 * AiProviderError — the wire-level 'error' event is the route layer's
 * translation), `extract()`, `verify()`, and `listModels()` where live.
 */
export const providers = { anthropic, openai, gemini, openrouter, ollama };
