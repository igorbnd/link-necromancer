#!/usr/bin/env bash
# SessionStart hook. stdout is added to the agent's context, so keep it to one screen.
# Reports presence of credentials only, never values.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0

echo "## Link Necromancer — session status"
echo
echo "Branch: $(git branch --show-current 2>/dev/null || echo '(not a git repo)')"

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "Working tree: dirty"
  git status --porcelain 2>/dev/null | head -15 | sed 's/^/  /'
else
  echo "Working tree: clean"
fi

echo
if [ -f package.json ]; then
  echo "Scaffolding: present"
  [ -d node_modules ] || echo "  node_modules missing — run 'pnpm install' before any test or typecheck"
else
  echo "Scaffolding: ABSENT. The starting point is core-pipeline task 1 (pnpm workspace setup)."
  echo "  Until package.json exists, the test and typecheck hooks no-op by design."
fi

echo
echo "Credentials (presence only):"
describe_absent() {
  case "$1" in
    NEBIUS_API_KEY) echo "absent — heuristics-only degraded mode, a supported path" ;;
    TAVILY_API_KEY) echo "absent — degraded discovery: redirect target and archive only" ;;
    GITHUB_TOKEN)   echo "absent — 'necro fix --pr' will exit 2; scanning is unaffected" ;;
    *)              echo "absent" ;;
  esac
}
for v in NEBIUS_API_KEY TAVILY_API_KEY GITHUB_TOKEN; do
  if [ -n "${!v:-}" ]; then
    echo "  $v: set"
  else
    echo "  $v: $(describe_absent "$v")"
  fi
done

echo
echo "Spec task progress (checked / total):"
shopt -s nullglob
for f in .kiro/specs/*/tasks.md; do
  total=$(grep -c '^- \[' "$f" 2>/dev/null || true)
  closed=$(grep -c '^- \[x\]' "$f" 2>/dev/null || true)
  printf '  %-22s %s/%s\n' "$(basename "$(dirname "$f")")" "${closed:-0}" "${total:-0}"
done
shopt -u nullglob

echo
echo "Build order: core-pipeline → necro-cli → graveyard-dashboard → github-action → mcp-server."
echo "Specs are the source of truth. Changing specified behaviour means updating the spec too."
