# Build context is the REPO ROOT (see docker-compose.yml) so the workspace lockfile is available.
FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/
RUN npm ci --omit=dev --workspace @alliswell/api

COPY apps/api apps/api

EXPOSE 3000
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:3000/health/live || exit 1

CMD ["node", "apps/api/src/server.js"]
