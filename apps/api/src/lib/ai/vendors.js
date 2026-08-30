/**
 * Who this instance can talk to, and who it can BILL against.
 *
 * These are two different lists and conflating them is how a meter acquires a
 * hole. Until now one constant did both jobs, written out twice (a route
 * schema and a migration) — which was survivable while every vendor could do
 * every job.
 *
 * `AI_PROVIDERS` — vendors with an adapter in `providers/`: they hold a
 * conversation, so a user may store a connection to one and a route may offer
 * one. This list is a promise about `chatStream()`.
 *
 * `AI_USAGE_PROVIDERS` — vendors whose work can appear in `ai_usage_events`.
 * A superset, because transcription vendors do exactly one thing and do not
 * belong in a chat connection: putting them in the first list would offer them
 * on a settings screen that would then fail at the first message. Leaving them
 * out of the SECOND list is worse though, and quietly so — `recordUsage` eats
 * its own errors by design ("a broken meter must never break a reply"), so a
 * vendor missing from the enum does not fail loudly. It just never appears in
 * the meter, and the usage report is short by however much that vendor did.
 */
export const AI_PROVIDERS = Object.freeze([
  'anthropic',
  'openai',
  'gemini',
  'openrouter',
  'ollama',
]);

/**
 * Transcription-only vendors: no `chatStream()`, so they are never connectable
 * as a chat provider, and every one of them still costs money that the meter
 * has to be able to name.
 *
 * Deepgram was here and is not any more (2026-08-31). It lost on the axis it
 * was picked for: on the two published multi-speaker benchmarks built from
 * real meeting audio it places seventh and second-to-last, and of the
 * candidates it is the only one whose Turkish arrived in 2026 and whose
 * Turkish is absent from its code-switching model. Its genuine strength is
 * latency, and transcribing a recording is not a latency problem.
 */
export const AI_TRANSCRIBE_ONLY_PROVIDERS = Object.freeze(['assemblyai', 'elevenlabs']);

export const AI_USAGE_PROVIDERS = Object.freeze([...AI_PROVIDERS, ...AI_TRANSCRIBE_ONLY_PROVIDERS]);
