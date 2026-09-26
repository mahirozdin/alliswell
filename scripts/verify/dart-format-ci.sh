#!/usr/bin/env bash
# CI's Dart formatter, run where CI's Dart can run — the Linux sandbox (ADR-0042, K2).
#
# The local Flutter SDK is newer than the 3.44.0 that ci.yml pins, and the two formatters
# disagree on collection layout ("tall style"): a file this machine calls formatted can turn
# CI's `dart format --set-exit-if-changed lib test` red, and did (a5d5a30). So the batch
# gate checks the changed Dart files with the Dart that Flutter 3.44.0 bundles.
#
#   bash scripts/verify/dart-format-ci.sh <file.dart>…                 check; exit 1 if any would change
#   DART_FORMAT_FIX=1 bash scripts/verify/dart-format-ci.sh <files>…   also print them, formatted, as a
#                                                                      tar on stdout (log goes to stderr)
#
# Paths are relative to the current directory. The files are copied into an empty directory
# first: with no analysis_options.yaml the page width is the default 80 — the app's own (its
# analysis_options has no formatter section) — and no stale .dart_tool can redirect it.
set -euo pipefail

DART_VERSION=3.12.0   # the Dart inside ci.yml's `flutter-version: 3.44.0` — change the two together
SDK_DIR=${DART_SDK_CACHE:-/srv/sandbox/tmp/dart-$DART_VERSION}

[ $# -gt 0 ] || { echo "dart-format-ci: no files given" >&2; exit 2; }

case "$(uname -m)" in
  x86_64) pkg=dartsdk-linux-x64-release.zip ;;
  aarch64 | arm64) pkg=dartsdk-linux-arm64-release.zip ;;
  *) echo "dart-format-ci: unsupported architecture $(uname -m)" >&2; exit 2 ;;
esac

# Only what `dart format` needs is unpacked (the VM, the dartdev snapshot, the SDK's own
# metadata): ~350 MB instead of ~930 MB at peak, on a disk other projects share.
if [ ! -x "$SDK_DIR/dart-sdk/bin/dart" ]; then
  mkdir -p "$SDK_DIR"
  (
    cd "$SDK_DIR"
    curl -sSfL -o sdk.zip "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/$pkg"
    python3 - <<'PY'
import os, stat, zipfile
keep = ('dart-sdk/bin/dart', 'dart-sdk/bin/dartaotruntime', 'dart-sdk/bin/snapshots/dartdev',
        'dart-sdk/bin/resources/', 'dart-sdk/version', 'dart-sdk/revision', 'dart-sdk/lib/_internal/')
with zipfile.ZipFile('sdk.zip') as z:
    z.extractall('.', members=[n for n in z.namelist() if n.startswith(keep)])
for exe in ('dart-sdk/bin/dart', 'dart-sdk/bin/dartaotruntime'):
    if os.path.exists(exe):
        os.chmod(exe, os.stat(exe).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY
    rm -f sdk.zip
  ) >&2
fi
dart="$SDK_DIR/dart-sdk/bin/dart"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for f in "$@"; do   # files, or whole directories (lib/ test/, as CI formats them)
  f=${f%/}
  mkdir -p "$work/$(dirname "$f")"
  cp -R "$f" "$work/$f"
done
cd "$work"
echo "$("$dart" --version 2>&1)" >&2
set +e
set -- "${@%/}"
"$dart" format --output=none --set-exit-if-changed "$@" > report.txt 2>&1
code=$?
set -e
changed=$(sed -n 's/^Changed //p' report.txt)
if [ -z "$changed" ] && [ "$code" -eq 0 ]; then
  echo "CI's formatter leaves $* as they are" >&2
  [ -n "${DART_FORMAT_FIX:-}" ] && tar -czf - --files-from /dev/null
  exit 0
fi
cat report.txt >&2
if [ -n "${DART_FORMAT_FIX:-}" ] && [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  "$dart" format $changed >&2
  # shellcheck disable=SC2086
  tar -czf - $changed
fi
echo "CI's formatter would change the file(s) above — the CI app job goes red on them" >&2
exit 1
