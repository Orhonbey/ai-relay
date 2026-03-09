#!/usr/bin/env bash
# ai-relay generic wrapper — config-driven AI CLI execution
# Usage: ./relay-run.sh [--worktree <path>] "prompt" [--continue [session_id]]

set -euo pipefail

CONFIG=".ai-relay.json"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG not found. Run install.sh first." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install: brew install jq" >&2
  exit 1
fi

# Read all config values in a single jq call
{
  read -r CLI
  read -r PROMPT_FLAGS
  read -r CONTINUE_FLAG
  read -r SESSION_FLAG
  read -r WORKDIR_FLAG
  read -r STATUS_FILE
} < <(jq -r '
  .cli,
  .flags.prompt,
  .flags.continue,
  .flags.session,
  .flags.workdir,
  (.status_file // ".relay_status")
' "$CONFIG")

# Validate status_file is a safe relative path
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

# Parse --worktree flag (must come before prompt)
WORKTREE_DIR=""
if [ "${1:-}" = "--worktree" ]; then
  WORKTREE_DIR="${2:-}"
  shift 2
  if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
    echo "ERROR: --worktree requires a valid directory path" >&2
    exit 1
  fi
fi

PROMPT="${1:-}"
shift || true

# Switch to worktree directory if provided
if [ -n "$WORKTREE_DIR" ]; then
  cd "$WORKTREE_DIR"
fi

echo "RUNNING" > "$STATUS_FILE"

# Build command as array to avoid shell injection via eval
CMD_ARGS=("$CLI")

# Split prompt flags on whitespace (controlled config values)
if [ -n "$PROMPT_FLAGS" ]; then
  read -ra PROMPT_FLAG_PARTS <<< "$PROMPT_FLAGS"
  CMD_ARGS+=("${PROMPT_FLAG_PARTS[@]}")
fi
CMD_ARGS+=("$PROMPT")

# Add workdir if flag exists
if [ -n "$WORKDIR_FLAG" ]; then
  read -ra WORKDIR_FLAG_PARTS <<< "$WORKDIR_FLAG"
  CMD_ARGS+=("${WORKDIR_FLAG_PARTS[@]}" "$(pwd)")
fi

# Handle --continue flag
if [ "${1:-}" = "--continue" ]; then
  shift
  if [ -n "$CONTINUE_FLAG" ]; then
    CMD_ARGS+=("$CONTINUE_FLAG")
  fi
  # Handle specific session ID
  if [ -n "${1:-}" ] && [ -n "$SESSION_FLAG" ]; then
    CMD_ARGS+=("$SESSION_FLAG" "$1")
    shift
  fi
fi

if "${CMD_ARGS[@]}"; then
  echo "DONE" > "$STATUS_FILE"
else
  echo "FAILED" > "$STATUS_FILE"
fi
