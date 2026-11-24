#!/usr/bin/env bash
# Stop hook. Refuses to let the turn end while the property tests are red.
#
# Exit 0 -> the turn finishes.
# Exit 1 -> Kiro starts another agent turn, using stderr as the reason.
#
# Skips entirely when nothing under packages/core or fixtures/ was touched, so an
# unrelated turn (docs, specs, dashboard styling) is not taxed with a test run.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0
[ -f package.json ] && [ -d node_modules ] || exit 0
command -v pnpm >/dev/null 2>&1 || exit 0

if [ -z "$(git status --porcelain -- packages/core fixtures 2>/dev/null)" ]; then
  exit 0
fi

if ! out=$(pnpm -s test:prop 2>&1); then
  {
    echo "The property tests are failing. Do not finish the turn here."
    echo
    echo "These six properties are the backbone of this project (see .kiro/steering/testing.md):"
    echo "URL normalization idempotence, byte-exact and invertible and idempotent edits,"
    echo "no links from code blocks, GitHub-compatible anchor slugs, one action per verdict."
    echo
    echo "Before fixing: copy the shrunk counterexample into a regression unit test."
    echo "If the property itself is wrong, change it deliberately and say why in the commit."
    echo
    echo "$out" | tail -40
  } >&2
  exit 1
fi

exit 0
