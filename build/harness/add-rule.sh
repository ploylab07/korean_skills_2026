#!/usr/bin/env bash
# Add or update a Cursor rule — Linux/Mac wrapper
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RULES_DIR="$ROOT/.cursor/rules"
TEMPLATE="$ROOT/build/harness/templates/rule.mdc.template"

usage() {
  cat <<'EOF'
Usage: ./build/harness/add-rule.sh --name NAME --description DESC [options]

Options:
  --always-apply       Rule applies to every session
  --globs PATTERN      File glob (when not always-apply)
  --content-file PATH  Markdown body from file
  --body TEXT          Inline markdown body
EOF
  exit 1
}

NAME=""
DESC=""
ALWAYS="false"
GLOBS=""
CONTENT_FILE=""
BODY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --description) DESC="$2"; shift 2 ;;
    --always-apply) ALWAYS="true"; shift ;;
    --globs) GLOBS="$2"; shift 2 ;;
    --content-file) CONTENT_FILE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1"; usage ;;
  esac
done

[[ -n "$NAME" && -n "$DESC" ]] || usage

mkdir -p "$RULES_DIR"
slug=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g;s/^-//;s/-$//')
rule_file="$RULES_DIR/${slug}.mdc"

if [[ -n "$CONTENT_FILE" ]]; then
  BODY=$(cat "$CONTENT_FILE")
fi

if [[ -z "$BODY" ]]; then
  BODY='## 규칙

- (여기에 규칙 내용을 작성하세요)'
fi

globs_line=""
if [[ -n "$GLOBS" && "$ALWAYS" != "true" ]]; then
  globs_line="globs: $GLOBS"
fi

title=$(echo "$NAME" | tr '-' ' ')

cat > "$rule_file" <<EOF
---
description: $DESC
${globs_line}
alwaysApply: $ALWAYS
---

# $title

$BODY
EOF

echo "Rule written: $rule_file"
