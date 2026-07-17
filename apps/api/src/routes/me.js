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

// Profile + workspaces for the authenticated user (no N+1: memberships, then
// their workspaces in one whereIn). Shared by GET and PATCH /me.
async function loadMe(app, userId) {
  const user = await app
    .db('users')
    .where({ id: userId })
    .whereNull('deleted_at')
    .first('id', 'email', 'display_name', 'avatar_url', 'timezone', 'locale', 'created_at');
  if (!user) {
    // Valid JWT for a user that no longer exists (deleted account).
    const err = app.httpErrors.unauthorized('Account no longer exists');
    err.code = 'AUTH_INVALID_TOKEN';
    throw err;
  }

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
}

// OPH-023 — the endpoint that closes Epic 03 (register → call an authenticated
// endpoint). OPH-126 adds PATCH for the account-level language preference so the
// chosen locale follows the user to a new device.
export default async function meRoutes(app) {
  app.get(
    '/me',
    {
      onRequest: [app.authenticate],
      schema: { response: { 200: meResponseSchema } },
    },
    async (request) => loadMe(app, request.user.id),
  );

  // OPH-126 — persist the user's language choice. Format-validated rather than
  // pinned to a fixed allow-list, so a self-hoster who drops in a new locale
  // file (ADR-0009) does not need an API change; the app decides what it ships.
  app.patch(
    '/me',
    {
      onRequest: [app.authenticate],
      schema: {
        body: {
          type: 'object',
          required: ['locale'],
          additionalProperties: false,
          properties: {
            locale: {
              type: 'string',
              // BCP-47 subset: `en`, `tr`, `en-US`, `pt-BR`, …
              pattern: '^[a-z]{2}(-[A-Za-z]{2,4})?$',
              maxLength: 16,
            },
          },
        },
        response: { 200: meResponseSchema },
      },
    },
    async (request) => {
      const updated = await app
        .db('users')
        .where({ id: request.user.id })
        .whereNull('deleted_at')
        .update({ locale: request.body.locale, updated_at: new Date() });
      if (updated === 0) {
        const err = app.httpErrors.unauthorized('Account no longer exists');
        err.code = 'AUTH_INVALID_TOKEN';
        throw err;
      }
      return loadMe(app, request.user.id);
    },
  );
}
