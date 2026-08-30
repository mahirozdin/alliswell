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
 *
 * `transcribe({ baseUrl, apiKey, model, audio, languageHint, signal })` is the
 * sixth member and the first OPTIONAL one: an adapter implements it only when
 * `capabilities().transcribe` is true, and callers must ask before calling.
 * It answers `{ transcript, usage }`, where `transcript` is the ONE shape
 * defined in `../transcript.js` — not the vendor's. Vendors disagree about
 * units, speaker types and even whether utterances exist, so the conversion
 * happens at the edge, in the adapter, and nothing above sees a vendor shape.
 *
 * `capabilities()` distinguishes `transcribe` from `diarize` on purpose: a
 * model that turns audio into words is not necessarily one that can be held to
 * telling speakers apart, and choosing a vendor on that guarantee rather than
 * on a feature list is the whole of AI-EE.md's argument.
 *
 * An extension may register adapters of its own against this same contract —
 * transcription vendors hold no conversation, so they are not registered here,
 * where every entry is a promise about `chatStream()`.
 */
export const providers = { anthropic, openai, gemini, openrouter, ollama };
