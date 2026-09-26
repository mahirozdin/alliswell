#!/usr/bin/env bash
# The remote half of scripts/verify/engine.mjs (ADR-0042). It runs ON the sandbox, from the
# freshly unpacked tree it arrived in. Two modes:
#
#   prep <profile> <base>   swap the unpacked tree in as <base>/<profile>, keeping the
#                           dependency install while the lockfiles are unchanged, and pull
#                           any image the compose file names that the host lacks
#   db <project> <name>     wait until the stack is healthy, then drop and recreate the
#                           database, so no row from an earlier run can decide a test
#
# Why a fresh tree every time instead of syncing over the last one: a file deleted here
# (a test, a migration) would otherwise live on there, and a migration that exists only on
# the sandbox changes what the chain means. The install is the expensive part and it
# depends only on the lockfiles, so it moves across unless they changed.
set -uo pipefail

mode=${1:?mode: prep | db}
shift

deps_dirs() {
  # Every node_modules the install produces: the root (hoisted), each workspace, and a
  # nested extension's own when it has one.
  local tree=$1
  printf '%s\n' node_modules
  for d in "$tree"/apps/*/ "$tree"/ee/; do
    [ -f "$d/package.json" ] && printf '%s\n' "${d#"$tree"/}node_modules"
  done
}

lock_stamp() {
  local tree=$1
  (cd "$tree" && cat package-lock.json ee/package-lock.json 2>/dev/null | md5sum | cut -d' ' -f1)
}

case "$mode" in
  prep)
    profile=${1:?profile}
    base=${2:?base}
    incoming=$(cd "$(dirname "$0")/../.." && pwd)
    tree="$base/$profile"
    stamp=$(lock_stamp "$incoming")
    if [ -f "$tree/.verify-lock" ] && [ "$(cat "$tree/.verify-lock")" = "$stamp" ]; then
      while read -r d; do
        [ -d "$tree/$d" ] && mkdir -p "$(dirname "$incoming/$d")" && mv "$tree/$d" "$incoming/$d"
      done < <(deps_dirs "$incoming")
      echo "deps: reused (lockfiles unchanged)"
    else
      echo "deps: lockfiles changed or first run — npm ci"
      (cd "$incoming" && npm ci --no-audit --no-fund --loglevel=error) || exit 1
      if [ -f "$incoming/ee/package.json" ]; then
        (cd "$incoming/ee" && npm ci --no-audit --no-fund --loglevel=error) || exit 1
      fi
    fi
    rm -rf "$tree"
    mv "$incoming" "$tree"
    echo "$stamp" > "$tree/.verify-lock"
    # `docker compose up` on this host does not pull what is missing (measured: mysql and
    # minio stayed "Created" behind a missing redis image), so pull first.
    for image in $(docker compose -f "$tree/docker-compose.yml" config --images 2>/dev/null); do
      docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null || exit 1
    done
    echo "tree: $tree ($(cd "$tree" && find . -path ./node_modules -prune -o -type f -print | wc -l) files)"
    ;;
  db)
    project=${1:?compose project}
    name=${2:?database name}
    mysql="${project}-mysql-1"
    for _ in $(seq 1 90); do
      state=$(docker inspect -f '{{.State.Health.Status}}' "$mysql" 2>/dev/null || echo missing)
      [ "$state" = healthy ] && break
      sleep 2
    done
    if [ "$state" != healthy ]; then
      echo "mysql is $state after 3 minutes — is the stack up (sbx up)?"
      docker logs --tail 20 "$mysql" 2>&1 | sed 's/^/  mysql: /'
      exit 1
    fi
    out=$(docker exec "$mysql" mysql -u"${DATABASE_USER:-alliswell}" -p"${DATABASE_PASSWORD:-alliswell_dev}" -e \
      "drop database if exists \`$name\`; create database \`$name\` character set utf8mb4 collate utf8mb4_0900_ai_ci" 2>&1)
    code=$?
    printf '%s\n' "$out" | grep -v 'Using a password' | sed '/^$/d'
    [ "$code" -eq 0 ] || { echo "database $name: could not recreate (exit $code)"; exit 1; }
    echo "database $name: recreated empty"
    ;;
  *)
    echo "unknown mode $mode" >&2
    exit 2
    ;;
esac
