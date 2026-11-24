#!/usr/bin/env bash
# PostFileSave hook for packages/core sources.
# Typechecks the package and runs the tests that import the saved file.
#
# Usage: check-core-save.sh <saved-file-path>
#
# No-ops silently until the workspace is scaffolded (core-pipeline task 1), so the
# hook can be committed now and becomes live the moment package.json lands.
set -uo pipefail

FILE="${1:-}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0
[ -f package.json ] && [ -d node_modules ] || exit 0
command -v pnpm >/dev/null 2>&1 || exit 0

status=0

if ! out=$(pnpm -s -C packages/core exec tsc --noEmit 2>&1); then
  {
    echo "Typecheck failed in packages/core:"
    echo "$out" | tail -30
  } >&2
  status=1
fi

# vitest 'related' runs only the test files that import this source file.
if [ -n "$FILE" ] && [ -f "$FILE" ]; then
  if ! out=$(pnpm -s exec vitest related "$FILE" --run 2>&1); then
    {
      echo "Tests related to $FILE are failing:"
      echo "$out" | tail -40
    } >&2
    status=1
  fi
fi

exit "$status"
