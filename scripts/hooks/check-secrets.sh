#!/usr/bin/env bash
# Credential scanner.
#
#   check-secrets.sh                  scan changed, staged and untracked files
#   check-secrets.sh --all            scan every tracked file (use in CI)
#   check-secrets.sh --from-hook-event  PreToolUse mode: read the hook event on stdin and
#                                       only act when the pending command is a git commit
#
# Exit 0 clean. Exit 2 in hook mode blocks the tool call. Exit 1 otherwise.
#
# This project records real HTTP responses into fixtures/cache/ and .necro-cache/, which is
# exactly the kind of file that carries an Authorization header in by accident. That is the
# leak this guards, more than a key pasted into source.
set -uo pipefail

MODE="${1:-changed}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0

if [ "$MODE" = "--from-hook-event" ]; then
  event=$(cat 2>/dev/null || true)
  # Match on the raw event text rather than a specific JSON field, so this keeps working
  # regardless of how the tool input is keyed.
  case "$event" in
    *"git commit"*) : ;;
    *) exit 0 ;;
  esac
fi

# Rule name, then the ERE. The name is what gets reported: a file, a line and the kind of
# secret is actionable, and unlike the matched text it cannot leak the value itself.
# ["']? after a key name is what lets these match inside recorded JSON fixtures.
RULES=(
  'env-var-assignment|(NEBIUS_API_KEY|TAVILY_API_KEY|GITHUB_TOKEN|ARCHIVE_ACCESS_KEY|ARCHIVE_SECRET_KEY)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_.-]{16,}'
  'tavily-key|tvly-[A-Za-z0-9]{16,}'
  'github-token|gh[pousr]_[A-Za-z0-9]{20,}'
  'bearer-header|[Aa]uthorization["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[Bb]earer[[:space:]]+[A-Za-z0-9._-]{16,}'
  'api-key-header|[Xx]-[Aa]pi-[Kk]ey["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9._-]{16,}'
  'private-key-block|-----BEGIN[A-Z ]*PRIVATE KEY-----'
  'jwt|eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.'
)

if [ "$MODE" = "--all" ]; then
  mapfile -t files < <(git ls-files 2>/dev/null)
else
  mapfile -t files < <(
    {
      git diff --name-only --diff-filter=ACMR 2>/dev/null
      git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
      git ls-files --others --exclude-standard 2>/dev/null
    } | sort -u
  )
fi

findings=()
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    .git/*|*/node_modules/*|node_modules/*) continue ;;
  esac
  # Skip binaries.
  grep -Iq . "$f" 2>/dev/null || continue

  for rule in "${RULES[@]}"; do
    name="${rule%%|*}"
    pattern="${rule#*|}"
    while IFS= read -r lineno; do
      [ -n "$lineno" ] && findings+=("  $f:$lineno  [$name]")
    done < <(grep -nE "$pattern" "$f" 2>/dev/null | cut -d: -f1)
  done
done

if [ "${#findings[@]}" -ne 0 ]; then
  {
    echo "Possible credentials found. Do not commit these."
    printf '%s\n' "${findings[@]}" | sort -u
    echo
    echo "Credentials belong in the environment only (see .kiro/steering/tech.md)."
    echo "If this is a recorded provider fixture, strip the request headers before committing;"
    echo "the cache layer should not persist them in the first place."
  } >&2
  [ "$MODE" = "--from-hook-event" ] && exit 2
  exit 1
fi

exit 0
