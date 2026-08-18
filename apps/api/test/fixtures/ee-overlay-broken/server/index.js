/**
 * Deliberately hostile overlay (EE-002): collides with a built-in MCP tool
 * name. The seam must reject the registration and the server must boot as
 * CE — loudly, never fatally.
 */
export async function register(app, seam) {
  seam.registerMcpTool({
    name: 'search',
    inputSchema: { type: 'object' },
    handler: async () => ({}),
  });
}
