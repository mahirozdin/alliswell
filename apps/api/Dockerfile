# AllisWell API — published as ghcr.io/<owner>/alliswell-api on every version tag.
# Build context is the REPO ROOT (see docker-compose.yml) so the workspace lockfile is available.
FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production
# What the process listens on INSIDE the container. Map it wherever you like
# (`-p 38005:3000`); no need to change this.
ENV PORT=3000
ENV HOST=0.0.0.0
# Apply pending migrations on start. Safe by design — migrations are
# append-only and idempotent (AGENTS.md rule 8), so `docker compose up` is all
# a self-hoster ever runs, including on upgrades. Set to "false" when a
# separate migration step owns the schema (multi-replica deployments).
ENV RUN_MIGRATIONS=true

COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/
RUN npm ci --omit=dev --workspace @alliswell/api

COPY apps/api apps/api
COPY docker/api-entrypoint.sh /usr/local/bin/alliswell-entrypoint
RUN chmod +x /usr/local/bin/alliswell-entrypoint

EXPOSE 3000
USER node

# Uses the configured port, so a remapped PORT stays self-checking.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health/live" || exit 1

ENTRYPOINT ["/usr/local/bin/alliswell-entrypoint"]
CMD ["node", "apps/api/src/server.js"]
