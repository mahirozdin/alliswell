#!/usr/bin/env bash
# Policy guard: this repository is JavaScript-only on the backend (see AGENTS.md).
# Fails if any TypeScript source file is tracked by git.
set -euo pipefail

files=$(git ls-files '*.ts' '*.tsx' '*.mts' '*.cts' || true)

if [ -n "$files" ]; then
  echo "ERROR: TypeScript files are forbidden by project policy (AGENTS.md → JavaScript-only):"
  echo "$files"
  exit 1
fi

echo "OK: no TypeScript files tracked."
