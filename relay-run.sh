#!/usr/bin/env bash
# ai-relay generic wrapper — config-driven AI CLI execution
# Usage: ./relay-run.sh [--target <name>] [--worktree <path>] "prompt" [--continue [session_id]]
#
# Config v3 resolves a named target (CLI x model) from .ai-relay.json.
# Config v1/v2 (no "version" key) is read as a single implicit target.

set -euo pipefail

CONFIG=".ai-relay.json"
AI_RELAY_HOME="${AI_RELAY_HOME:-$HOME/.ai-relay}"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found. Run install.sh first." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install: brew install jq" >&2
  exit 1
fi

# --- Parse leading flags -----------------------------------------------------
TARGET=""
WORKTREE_DIR=""
while :; do
  case "${1:-}" in
    --target)
      TARGET="${2:-}"
      shift 2 || { echo "ERROR: --target requires a name" >&2; exit 1; }
      ;;
    --worktree)
      WORKTREE_DIR="${2:-}"
      shift 2 || { echo "ERROR: --worktree requires a path" >&2; exit 1; }
      if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
        echo "ERROR: --worktree requires a valid directory path" >&2
        exit 1
      fi
      ;;
    *) break ;;
  esac
done

PROMPT="${1:-}"
shift || true
if [ -z "$PROMPT" ]; then
  echo "ERROR: no prompt given" >&2
  exit 1
fi

# --- Resolve config ----------------------------------------------------------
CONFIG_VERSION="$(jq -r '.version // 2' "$CONFIG")"
STATUS_FILE="$(jq -r '.status_file // ".relay_status"' "$CONFIG")"

if [ "$CONFIG_VERSION" -ge 3 ] 2>/dev/null; then
  [ -n "$TARGET" ] || TARGET="$(jq -r '.default_target // empty' "$CONFIG")"
  if [ -z "$TARGET" ]; then
    echo "ERROR: no --target given and no default_target in $CONFIG" >&2
    exit 1
  fi

  TARGET_JSON="$(jq -c --arg t "$TARGET" '.targets[$t] // empty' "$CONFIG")"
  if [ -z "$TARGET_JSON" ]; then
    echo "ERROR: unknown target '$TARGET'. Available targets:" >&2
    jq -r '.targets | keys[] | "  - " + .' "$CONFIG" >&2
    exit 1
  fi

  PRESET_NAME="$(printf '%s' "$TARGET_JSON" | jq -r '.preset // .cli // empty')"
  PRESET_FILE="$AI_RELAY_HOME/presets/$PRESET_NAME.json"
  if [ ! -f "$PRESET_FILE" ]; then
    echo "ERROR: preset '$PRESET_NAME' not found at $PRESET_FILE" >&2
    echo "       Run install.sh to refresh $AI_RELAY_HOME/presets/" >&2
    exit 1
  fi

  # Target-level flags override preset flags key by key.
  RESOLVED="$(jq -n \
    --slurpfile preset "$PRESET_FILE" \
    --argjson target "$TARGET_JSON" \
    '{
       cli:   ($target.cli   // $preset[0].cli),
       model: ($target.model // ""),
       flags: (($preset[0].flags // {}) * ($target.flags // {}))
     }')"
else
  RESOLVED="$(jq -c '{ cli: .cli, model: "", flags: (.flags // {}) }' "$CONFIG")"
fi

CLI="$(printf '%s' "$RESOLVED"        | jq -r '.cli')"
MODEL="$(printf '%s' "$RESOLVED"      | jq -r '.model // ""')"
PRE_FLAGS="$(printf '%s' "$RESOLVED"  | jq -r '.flags.pre // ""')"
MODEL_FLAG="$(printf '%s' "$RESOLVED" | jq -r '.flags.model // ""')"
PROMPT_FLAGS="$(printf '%s' "$RESOLVED" | jq -r '.flags.prompt // ""')"
CONTINUE_FLAG="$(printf '%s' "$RESOLVED" | jq -r '.flags.continue // ""')"
SESSION_FLAG="$(printf '%s' "$RESOLVED"  | jq -r '.flags.session // ""')"
WORKDIR_FLAG="$(printf '%s' "$RESOLVED"  | jq -r '.flags.workdir // ""')"

if [ -z "$CLI" ] || [ "$CLI" = "null" ]; then
  echo "ERROR: no cli resolved from $CONFIG" >&2
  exit 1
fi

# --- Validate status file path ----------------------------------------------
case "$STATUS_FILE" in
  /*|../*|*/../*)
    echo "ERROR: status_file must be a relative path within the project" >&2
    exit 1
    ;;
esac

if [ -L "$STATUS_FILE" ]; then
  echo "ERROR: status_file is a symlink — refusing to write" >&2
  exit 1
fi

# --- Switch to worktree ------------------------------------------------------
if [ -n "$WORKTREE_DIR" ]; then
  cd "$WORKTREE_DIR"
fi

echo "RUNNING" > "$STATUS_FILE"

# --- Build the command as an array (no eval, no injection) -------------------
CMD_ARGS=("$CLI")

append_flags() {
  # Splits a controlled config string on whitespace and appends each word.
  local raw="$1"
  local -a parts
  [ -n "$raw" ] || return 0
  read -ra parts <<< "$raw"
  CMD_ARGS+=("${parts[@]}")
}

append_flags "$PRE_FLAGS"

if [ -n "$MODEL_FLAG" ] && [ -n "$MODEL" ]; then
  append_flags "$MODEL_FLAG"
  CMD_ARGS+=("$MODEL")
fi

append_flags "$PROMPT_FLAGS"
CMD_ARGS+=("$PROMPT")

if [ -n "$WORKDIR_FLAG" ]; then
  append_flags "$WORKDIR_FLAG"
  CMD_ARGS+=("$(pwd)")
fi

if [ "${1:-}" = "--continue" ]; then
  shift
  if [ -n "$CONTINUE_FLAG" ]; then
    append_flags "$CONTINUE_FLAG"
  fi
  if [ -n "${1:-}" ] && [ -n "$SESSION_FLAG" ]; then
    append_flags "$SESSION_FLAG"
    CMD_ARGS+=("$1")
    shift
  fi
fi

if "${CMD_ARGS[@]}"; then
  echo "DONE" > "$STATUS_FILE"
else
  echo "FAILED" > "$STATUS_FILE"
fi
