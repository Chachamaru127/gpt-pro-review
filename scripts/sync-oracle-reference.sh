#!/usr/bin/env bash
# Sync reference metadata from the sibling oracle repo (steipete/oracle fork).
# Does not vendor the full oracle codebase — records commit + pattern notes only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/oracle"
ORACLE_DIR="${ORACLE_DIR:-$(cd "$ROOT/.." && pwd)/oracle}"

if [ ! -d "$ORACLE_DIR/.git" ]; then
  echo "[sync-oracle-reference] oracle repo not found at: $ORACLE_DIR" >&2
  echo "Set ORACLE_DIR=/path/to/oracle or clone oracle next to gpt-pro-review." >&2
  exit 2
fi

mkdir -p "$VENDOR/refs"

echo "[sync-oracle-reference] fetching in $ORACLE_DIR" >&2
git -C "$ORACLE_DIR" fetch origin --quiet
git -C "$ORACLE_DIR" pull --ff-only origin HEAD 2>/dev/null || git -C "$ORACLE_DIR" pull --ff-only

COMMIT=$(git -C "$ORACLE_DIR" rev-parse HEAD)
DATE=$(git -C "$ORACLE_DIR" log -1 --format=%ci)
BRANCH=$(git -C "$ORACLE_DIR" rev-parse --abbrev-ref HEAD)

printf '%s\n' "$COMMIT" > "$VENDOR/SYNCED_COMMIT"
printf '%s\n' "$DATE" > "$VENDOR/SYNCED_AT"
printf '%s\n' "$BRANCH" > "$VENDOR/SYNCED_BRANCH"

# Lightweight refs for diff review (not compiled into runtime)
for rel in \
  src/browser/actions/thinkingStatus.ts \
  src/browser/actions/assistantResponse.ts \
  src/browser/actions/promptComposer.ts \
  docs/agents.md
do
  src="$ORACLE_DIR/$rel"
  if [ -f "$src" ]; then
    dest="$VENDOR/refs/$(echo "$rel" | tr '/' '__')"
    cp "$src" "$dest"
  fi
done

echo "[sync-oracle-reference] synced $COMMIT ($BRANCH @ $DATE)"
echo "See docs/oracle-adoptions.md for what gpt-pro-review adopted from oracle."
