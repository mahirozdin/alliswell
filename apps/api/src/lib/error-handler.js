import { STATUS_CODES } from 'node:http';
import sensible from '@fastify/sensible';

/**
 * The root error handler (OPH-357, AGENTS §4 "never leak internals").
 *
 * Fastify's default handler answers every error with its own `message` and
 * `code` — fine for the 4xx a route wrote on purpose, a leak for everything
 * else: a strict-mode MySQL failure came back as a 500 whose body was the full
 * INSERT statement, with table, column and user ids in it. The split:
 *
 * - **4xx** — unchanged. Handed back to Fastify's default handler, which
 *   produces exactly the body it always did (validation errors included).
 *   The one addition is `retryAfter` on the limiter's `RATE_LIMITED` 429. A
 *   thrown plain object (a route limiter's own body) keeps its status code.
 * - **5xx written on purpose** — an `HttpError` from `app.httpErrors`
 *   (`serviceUnavailable('…not configured')`, `badGateway(...)`): its author
 *   chose the words and the code, and clients branch on them. Unchanged.
 * - **anything else ≥ 500** — a thrown library/driver/runtime error. The body
 *   becomes a fixed `INTERNAL_ERROR`; the real error goes to the log with the
 *   request id, which is where an operator looks for it.
 *
 * A plugin with its own `setErrorHandler` (the extension's public portal and
 * customer portal render HTML) keeps it: Fastify resolves the innermost
 * handler first, and this one is only the root's.
 *
 * @param {Error & { statusCode?: number, status?: number, code?: string, retryAfter?: number }} error
 * @param {import('fastify').FastifyRequest} request
 * @param {import('fastify').FastifyReply} reply
 */
export function rootErrorHandler(error, request, reply) {
  const raw = error?.statusCode ?? error?.status;
  const statusCode = Number.isInteger(raw) && raw >= 400 && raw <= 599 ? raw : 500;

  if (statusCode < 500) {
    if (error.code === 'RATE_LIMITED' && Number.isInteger(error.retryAfter)) {
      reply.code(statusCode);
      return reply.send({
        statusCode,
        code: error.code,
        error: STATUS_CODES[statusCode],
        message: error.message,
        retryAfter: error.retryAfter,
      });
    }
    // A plain object is not an Error: `reply.send` would serialize it with
    // whatever status the reply holds (200), turning a refusal into a success.
    // @fastify/rate-limit throws exactly that when a route's
    // `errorResponseBuilder` returns a body (the extension's sales shield).
    if (!(error instanceof Error)) return reply.code(statusCode).send(error);
    // Fastify's default handler, i.e. the body every 4xx always had.
    return reply.send(error);
  }

  if (error instanceof sensible.HttpError) return reply.send(error);

  request.log.error({ err: error }, 'unhandled error');
  reply.code(statusCode);
  return reply.send({
    statusCode,
    code: 'INTERNAL_ERROR',
    error: 'Internal Server Error',
    message: 'Internal server error',
  });
}
