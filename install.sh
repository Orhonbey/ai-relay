#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "ai-relay installer"
echo "==================="
echo ""

# 1. Skill -> global commands
DEST="${HOME}/.claude/commands/relay.md"
mkdir -p "$(dirname "$DEST")"
cp "$SCRIPT_DIR/relay.md" "$DEST"
echo "  Skill installed: $DEST"

# 2. Runner -> current project
cp "$SCRIPT_DIR/relay-run.sh" ./relay-run.sh
chmod +x ./relay-run.sh
echo "  Runner copied: ./relay-run.sh"

# 3. Config from preset or template
PRESET="${1:-}"
if [ -n "$PRESET" ] && [ -f "$SCRIPT_DIR/presets/$PRESET.json" ]; then
  cp "$SCRIPT_DIR/presets/$PRESET.json" .ai-relay.json
  echo "  Config from preset: $PRESET"
else
  cp "$SCRIPT_DIR/.ai-relay.json.example" .ai-relay.json
  echo "  Template config created. Set 'cli' and 'flags' in .ai-relay.json"
  [ -z "$PRESET" ] || echo "  WARNING: Preset '$PRESET' not found, using blank config"
fi

# 4. Add to .gitignore if not already there
if [ -f .gitignore ]; then
  grep -qxF '.relay_status' .gitignore || echo '.relay_status' >> .gitignore
  grep -qxF '.ai-relay.json' .gitignore || echo '.ai-relay.json' >> .gitignore
else
  printf '.relay_status\n.ai-relay.json\n' > .gitignore
fi
echo "  .gitignore updated"

echo ""
echo "Done! Usage: /relay <task description>"
