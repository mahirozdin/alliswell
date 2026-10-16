/**
 * Refusals the importers raise (OPH-371, ADR-0052). Plain errors with an HTTP
 * status and a stable `code`, so the pure parsers need neither Fastify nor
 * `@fastify/sensible` and the route can pass them straight through.
 */
export function importError(statusCode, code, message, extra = {}) {
  return Object.assign(new Error(message), { statusCode, code, ...extra });
}
