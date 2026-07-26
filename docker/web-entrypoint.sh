#!/bin/sh
# Writes the runtime configuration the Flutter bundle reads on boot
# (web/alliswell-config.js → window.ALLISWELL_API_URL → apiBaseUrlProvider).
#
# nginx:alpine runs everything in /docker-entrypoint.d/ before starting nginx,
# so this happens once per container start — the image itself stays generic and
# identical for every deployment.
set -eu

CONFIG=/usr/share/nginx/html/alliswell-config.js

if [ -z "${ALLISWELL_API_URL:-}" ]; then
  echo "alliswell-web: WARNING — ALLISWELL_API_URL is not set." >&2
  echo "alliswell-web: the app will fall back to http://localhost:3000, which" >&2
  echo "alliswell-web: only works if the API happens to be on the viewer's own" >&2
  echo "alliswell-web: machine. Set it to your API origin, e.g." >&2
  echo "alliswell-web:   -e ALLISWELL_API_URL=https://api.your-domain.example" >&2
  exit 0
fi

# JSON-encode the value so quotes or backslashes cannot break out of the string.
escaped=$(printf '%s' "$ALLISWELL_API_URL" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

cat > "$CONFIG" <<EOF
// Generated at container start from ALLISWELL_API_URL — do not edit.
window.ALLISWELL_API_URL = "$escaped";
EOF

echo "alliswell-web: API base URL set to $ALLISWELL_API_URL"
