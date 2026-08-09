#!/usr/bin/env bash
#
# OPH-244 (DESIGN §30 A3) — the Android release APK declares EXACTLY the
# permissions we intend, and nothing a dependency slipped in.
#
# Why an artifact check and not a unit test: no Dart test can see the merged
# manifest. Plugins contribute `<uses-permission>` entries at build time, and
# `tools:node="remove"` is silent when it matches nothing — so the only place
# the truth exists is the built package. Play scans the APK's binary manifest,
# so that is what this reads; `build/app/intermediates/merged_manifests/…` is
# one step earlier and can differ.
#
# An exact-set diff, deliberately, rather than grepping for the permissions we
# fear. The dangerous permission is the one nobody anticipated; an allowlist
# catches that and a denylist cannot.
#
# The allowlist is populated from a real build, never guessed:
#   bash scripts/android/assert-permissions.sh --write
#
set -euo pipefail

cd "$(dirname "$0")/../.."
APP_DIR="apps/app"
ALLOWLIST="scripts/android/allowed-permissions.txt"
APK="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

find_aapt2() {
  if command -v aapt2 >/dev/null 2>&1; then command -v aapt2; return; fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  # Newest build-tools wins.
  find "$sdk/build-tools" -maxdepth 2 -name aapt2 -type f 2>/dev/null | sort -V | tail -1
}

if [ ! -f "$APK" ]; then
  echo "Building the release APK first (the manifest only exists in the build)…"
  (cd "$APP_DIR" && flutter build apk --release --target-platform android-arm64)
fi

AAPT2="$(find_aapt2)"
if [ -z "$AAPT2" ] || [ ! -x "$AAPT2" ]; then
  echo "FAIL: aapt2 not found. Install Android build-tools or set ANDROID_HOME." >&2
  exit 2
fi

ACTUAL="$("$AAPT2" dump permissions "$APK" \
  | grep '^uses-permission:' \
  | sed "s/.*name='\([^']*\)'.*/\1/" \
  | sort -u)"

if [ "${1:-}" = "--write" ]; then
  printf '%s\n' "$ACTUAL" > "$ALLOWLIST"
  echo "Wrote $ALLOWLIST:"
  printf '%s\n' "$ACTUAL" | sed 's/^/  /'
  exit 0
fi

if [ ! -f "$ALLOWLIST" ]; then
  echo "FAIL: $ALLOWLIST is missing. Run with --write after a real build." >&2
  exit 2
fi

if diff -u "$ALLOWLIST" <(printf '%s\n' "$ACTUAL"); then
  echo "OK: the release APK declares exactly the $(wc -l < "$ALLOWLIST" | tr -d ' ') intended permissions."
else
  cat >&2 <<'MSG'

FAIL: the release APK's permissions changed.

A "+" line is a permission a dependency added. If it is a media permission
(READ_MEDIA_*, READ_EXTERNAL_STORAGE, CAMERA) that is a Play policy problem,
not a formality — strip it with tools:node="remove" in
apps/app/android/app/src/main/AndroidManifest.xml.

If the change is intended, re-run with --write and explain it in the commit.
MSG
  exit 1
fi
