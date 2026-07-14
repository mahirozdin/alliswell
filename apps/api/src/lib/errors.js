/**
 * Attaches a stable machine-readable `code` (AGENTS.md §4) to an
 * @fastify/sensible HTTP error:
 *
 *   throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
 */
export function coded(httpError, code) {
  httpError.code = code;
  return httpError;
}
