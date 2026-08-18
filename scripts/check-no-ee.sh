#!/usr/bin/env bash
# Policy guard: the Enterprise Edition lives in a PRIVATE repo checked out at
# ee/ (nested overlay). Nothing of it may ever be tracked by the public repo —
# .gitignore blocks the normal path, but `git add -f` walks straight past it.
# Two real vectors, both caught by the bare `ee` pathspec (which matches the
# path itself AND everything under it):
#   1. `git add -f ee` once the nested repo has commits → a gitlink entry at
#      path `ee` (mode 160000) that references a private SHA and breaks clones.
#      A pathspec of 'ee/*' does NOT see this entry — measured, not guessed.
#   2. ee/.git lost (tool copy, partial checkout) → `git add -f` tracks the
#      actual files, i.e. publishes commercial code irreversibly.
set -euo pipefail

files=$(git ls-files -- ee || true)

if [ -n "$files" ]; then
  echo "ERROR: 'ee' is tracked by the public repo (gitlink or files). The EE overlay is"
  echo "private by design (see AGENTS.md and the EE repo's ADR-0001). Untrack immediately:"
  echo "$files"
  exit 1
fi

echo "OK: nothing under ee is tracked."
