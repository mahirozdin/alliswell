/**
 * JSON-RPC 2.0 envelope helpers for the hand-rolled MCP server (OPH-218,
 * ADR-0022 §1). Stateless Streamable HTTP: one message per POST, one JSON
 * response, no batching (removed in protocol 2025-06-18 — the 2025-03-26
 * degradation is deliberate).
 */

export const RPC = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
  RESOURCE_NOT_FOUND: -32002,
};

export const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26'];
export const LATEST_PROTOCOL = PROTOCOL_VERSIONS[0];

export function rpcResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

export function rpcError(id, code, message, data) {
  return { jsonrpc: '2.0', id: id ?? null, error: { code, message, ...(data ? { data } : {}) } };
}

/** A structurally valid single JSON-RPC request (not an array, not junk). */
export function isValidRequest(message) {
  return (
    message !== null &&
    typeof message === 'object' &&
    !Array.isArray(message) &&
    message.jsonrpc === '2.0' &&
    typeof message.method === 'string'
  );
}

export function isNotification(message) {
  return isValidRequest(message) && message.id === undefined;
}

/** Wraps a tool payload into the spec's dual content + structuredContent form. */
export function toolResult(payload, { isError = false } = {}) {
  return {
    content: [{ type: 'text', text: JSON.stringify(payload) }],
    structuredContent: payload,
    isError,
  };
}

/** Domain refusals are tool RESULTS (model-correctable), never protocol errors. */
export class McpToolError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'McpToolError';
    this.code = code;
  }
}
