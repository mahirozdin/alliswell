/**
 * Overlay whose MCP tool says who it is for with something that cannot be
 * asked (EE-291). The seam must refuse the registration, and the server must
 * lock loudly, never fatally — the path every refused registration takes
 * (OPH-343).
 */
export async function register(app, seam) {
  seam.registerMcpTool({
    name: 'seam_bad_offer_tool',
    inputSchema: { type: 'object' },
    available: 'everyone',
    handler: async () => ({}),
  });
}
