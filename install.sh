#!/usr/bin/env bash
# ai-relay installer
# Usage: ./install.sh [preset]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_RELAY_HOME="${AI_RELAY_HOME:-$HOME/.ai-relay}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

echo "ai-relay installer"
echo "==================="
echo ""

# 1. Runner + presets -> global home (not the project)
mkdir -p "$AI_RELAY_HOME/presets"
cp "$SCRIPT_DIR/relay-run.sh" "$AI_RELAY_HOME/relay-run.sh"
chmod +x "$AI_RELAY_HOME/relay-run.sh"
cp "$SCRIPT_DIR"/presets/*.json "$AI_RELAY_HOME/presets/"
echo "  Runner installed:  $AI_RELAY_HOME/relay-run.sh"
echo "  Presets installed: $AI_RELAY_HOME/presets/"

# 2. Skill + slash command -> Claude home
mkdir -p "$CLAUDE_HOME/commands" "$CLAUDE_HOME/skills/ai-relay"
cp "$SCRIPT_DIR/relay.md" "$CLAUDE_HOME/commands/relay.md"
cp "$SCRIPT_DIR/SKILL.md" "$CLAUDE_HOME/skills/ai-relay/SKILL.md"
cp "$SCRIPT_DIR/relay.md" "$CLAUDE_HOME/skills/ai-relay/relay.md"
mkdir -p "$CLAUDE_HOME/skills/ai-relay/templates"
cp "$SCRIPT_DIR/templates/plan.md" "$CLAUDE_HOME/skills/ai-relay/templates/plan.md"
echo "  Skill installed:   $CLAUDE_HOME/skills/ai-relay/"
echo "  Command installed: $CLAUDE_HOME/commands/relay.md"

# 3. Project config
PRESET="${1:-}"
if [ -f .ai-relay.json ]; then
  echo "  Config exists:     ./.ai-relay.json (left untouched)"
elif [ -n "$PRESET" ] && [ -f "$SCRIPT_DIR/presets/$PRESET.json" ]; then
  jq -n --arg p "$PRESET" --slurpfile preset "$SCRIPT_DIR/presets/$PRESET.json" '{
    version: 3,
    plan: { dir: "docs/relay-plans" },
    targets: { ($p): { preset: $p, model: "" } },
    default_target: $p,
    escalation: [$p],
    max_retries: 3,
    gates: [],
    worktree: { enabled: true, base_dir: ".worktrees" },
    status_file: ".relay_status"
  }' > .ai-relay.json
  echo "  Config created:    ./.ai-relay.json (target '$PRESET' — set .targets.$PRESET.model)"
else
  cp "$SCRIPT_DIR/.ai-relay.json.example" .ai-relay.json
  echo "  Config created:    ./.ai-relay.json from template — edit targets and gates"
  [ -z "$PRESET" ] || echo "  WARNING: preset '$PRESET' not found, used template"
fi

# 4. .gitignore — config is now a tracked project fact
if [ -f .gitignore ]; then
  # Remove the v2 line that ignored the config.
  if grep -qxF '.ai-relay.json' .gitignore; then
    grep -vxF '.ai-relay.json' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
    echo "  .gitignore:        removed .ai-relay.json (config is committed in v3)"
  fi
  grep -qxF '.relay_status' .gitignore || echo '.relay_status' >> .gitignore
  grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
else
  printf '.relay_status\n.worktrees/\n' > .gitignore
fi
echo "  .gitignore updated"

echo ""
echo "Done. Usage: /relay <task description>"
