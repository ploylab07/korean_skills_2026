#!/usr/bin/env bash
# Configure Cursor hooks for Linux/Mac (bash hooks)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="$ROOT/.cursor/hooks.json"
HOOKS_DIR="$ROOT/.cursor/hooks"

mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_FILE" <<'EOF'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {
        "command": ".cursor/hooks/after-tf-edit.sh",
        "matcher": "\\.tf$"
      }
    ],
    "stop": [
      {
        "command": ".cursor/hooks/stop-harness.sh"
      }
    ]
  }
}
EOF

chmod +x "$HOOKS_DIR"/*.sh 2>/dev/null || true
echo "Unix hooks installed: $HOOKS_FILE"
