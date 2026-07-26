#!/bin/sh
# AllisWell API container entrypoint.
#
# Waits for MySQL/MariaDB to accept the schema, applies pending migrations, then
# hands off to the server. Self-hosters run one command (`docker compose up`)
# and upgrades are just a newer image tag — the schema catches up on its own.
set -eu

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  # The database container is usually still starting on a fresh `compose up`,
  # and knex fails fast rather than waiting. Retry briefly instead of making
  # every user discover `depends_on: condition: service_healthy`.
  attempt=1
  max=30
  until npm run --silent db:migrate; do
    if [ "$attempt" -ge "$max" ]; then
      echo "alliswell: migrations failed after $max attempts — giving up." >&2
      exit 1
    fi
    echo "alliswell: database not ready (attempt $attempt/$max), retrying in 2s…" >&2
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "alliswell: schema is up to date."
fi

exec "$@"
