const meResponseSchema = {
  type: 'object',
  required: ['user', 'workspaces'],
  properties: {
    user: {
      type: 'object',
      required: ['id', 'email', 'timezone', 'locale', 'createdAt'],
      properties: {
        id: { type: 'string' },
        email: { type: 'string' },
        displayName: { type: ['string', 'null'] },
        avatarUrl: { type: ['string', 'null'] },
        timezone: { type: 'string' },
        locale: { type: 'string' },
        createdAt: { type: 'string' },
      },
    },
    workspaces: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'name', 'slug', 'role'],
        properties: {
          id: { type: 'string' },
          name: { type: 'string' },
          slug: { type: 'string' },
          colorRgb: { type: 'string' },
          icon: { type: ['string', 'null'] },
          role: { type: 'string', enum: ['owner', 'admin', 'member'] },
        },
      },
    },
  },
};

// OPH-023 — profile + workspaces for the authenticated user. This endpoint also
// closes the Epic 03 acceptance: register → call an authenticated endpoint.
export default async function meRoutes(app) {
  app.get(
    '/me',
    {
      onRequest: [app.authenticate],
      schema: { response: { 200: meResponseSchema } },
    },
    async (request) => {
      const user = await app
        .db('users')
        .where({ id: request.user.id })
        .whereNull('deleted_at')
        .first('id', 'email', 'display_name', 'avatar_url', 'timezone', 'locale', 'created_at');
      if (!user) {
        // Valid JWT for a user that no longer exists (deleted account).
        const err = app.httpErrors.unauthorized('Account no longer exists');
        err.code = 'AUTH_INVALID_TOKEN';
        throw err;
      }

      // Two batched queries (no N+1): memberships, then their workspaces.
      const memberships = await app
        .db('workspace_members')
        .where({ user_id: user.id })
        .select('workspace_id', 'role');
      const roleByWorkspace = new Map(memberships.map((m) => [m.workspace_id, m.role]));

      const workspaces =
        memberships.length === 0
          ? []
          : await app
              .db('workspaces')
              .whereIn('id', [...roleByWorkspace.keys()])
              .whereNull('deleted_at')
              .select('id', 'name', 'slug', 'color_rgb', 'icon');

      return {
        user: {
          id: user.id,
          email: user.email,
          displayName: user.display_name ?? null,
          avatarUrl: user.avatar_url ?? null,
          timezone: user.timezone,
          locale: user.locale,
          createdAt: new Date(user.created_at).toISOString(),
        },
        workspaces: workspaces.map((ws) => ({
          id: ws.id,
          name: ws.name,
          slug: ws.slug,
          colorRgb: ws.color_rgb,
          icon: ws.icon ?? null,
          role: roleByWorkspace.get(ws.id),
        })),
      };
    },
  );
}
