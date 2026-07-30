/**
 * The model catalog (OPH-216, AI.md §9): a static curated list for the four
 * cloud providers, live `/api/tags` for Ollama (the only provider whose list
 * is genuinely instance-specific — cloud rosters are noisy snapshots, and a
 * live call per settings-open would spend the user's quota on chrome).
 *
 * This is DATA, refreshed at the standing quarterly provider re-check
 * (STATE "Kullanıcıdan bekleyen"). Model ids are never hard-validated against
 * it — a brand-new model id must not be blocked by our staleness, so
 * free-form overrides stay legal (OPH-215 decision).
 *
 * Class policy (ADR-0019 cost ceiling): `chat` defaults to the mid class,
 * `fast` (extraction/intent) to the cheap class. Gemini's chat default is
 * Flash, not Pro — the free tier is Flash-only (AI.md §1) and a default that
 * 402s for free-tier users would be a lie.
 */
export const MODEL_CATALOG = {
  anthropic: {
    chat: [
      { id: 'claude-sonnet-5', label: 'Claude Sonnet 5' },
      { id: 'claude-opus-5', label: 'Claude Opus 5' },
    ],
    fast: [{ id: 'claude-haiku-4-5-20251001', label: 'Claude Haiku 4.5' }],
    defaults: { chat: 'claude-sonnet-5', fast: 'claude-haiku-4-5-20251001' },
  },
  openai: {
    chat: [
      { id: 'gpt-5.1', label: 'GPT-5.1' },
      { id: 'gpt-5', label: 'GPT-5' },
    ],
    fast: [
      { id: 'gpt-5-mini', label: 'GPT-5 mini' },
      { id: 'gpt-5-nano', label: 'GPT-5 nano' },
    ],
    defaults: { chat: 'gpt-5.1', fast: 'gpt-5-mini' },
  },
  gemini: {
    chat: [
      { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash' },
      { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro' },
    ],
    fast: [
      { id: 'gemini-2.5-flash-lite', label: 'Gemini 2.5 Flash-Lite' },
      { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash' },
    ],
    defaults: { chat: 'gemini-2.5-flash', fast: 'gemini-2.5-flash-lite' },
  },
  openrouter: {
    chat: [
      { id: 'anthropic/claude-sonnet-5', label: 'Claude Sonnet 5 (OpenRouter)' },
      { id: 'openai/gpt-5.1', label: 'GPT-5.1 (OpenRouter)' },
    ],
    fast: [
      { id: 'anthropic/claude-haiku-4.5', label: 'Claude Haiku 4.5 (OpenRouter)' },
      { id: 'openai/gpt-5-mini', label: 'GPT-5 mini (OpenRouter)' },
    ],
    defaults: { chat: 'anthropic/claude-sonnet-5', fast: 'anthropic/claude-haiku-4.5' },
  },
  ollama: { live: true },
};

/**
 * Factory defaults for a provider. Ollama has none statically — its defaults
 * resolve from the instance's tags at request time (fast = chat there: a
 * self-host usually pulls one model).
 */
export function catalogDefaults(provider) {
  const entry = MODEL_CATALOG[provider];
  if (!entry || entry.live) return { chat: null, fast: null };
  return { ...entry.defaults };
}
