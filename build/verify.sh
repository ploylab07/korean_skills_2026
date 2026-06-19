#!/usr/bin/env bash
# Repository smoke test — Terraform wrapper, env loading, init/validate/plan
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
SMOKE_DIR="$ROOT/build/smoke"
PASS=0
FAIL=0
SKIP=0

green() { printf '\033[32m✓\033[0m %s\n' "$1"; }
red()   { printf '\033[31m✗\033[0m %s\n' "$1"; }
yellow(){ printf '\033[33m-\033[0m %s\n' "$1"; }

pass() { green "$1"; PASS=$((PASS + 1)); }
fail() { red "$1"; FAIL=$((FAIL + 1)); }
skip() { yellow "$1 (skip)"; SKIP=$((SKIP + 1)); }

run_check() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

echo "=== Korean Skills 2026 — smoke verify ==="
echo "root: $ROOT"
echo

# 1. Wrapper files
run_check "terraform wrapper exists" test -x "$TF"
run_check "setup-aws exists" test -x "$ROOT/setup-aws"
run_check "build/terraform exists" test -x "$ROOT/build/terraform"
run_check ".env.example exists" test -f "$ROOT/.env.example"

# 2. Version
if "$TF" version 2>&1 | grep -q "Terraform v"; then
  pass "terraform version runs"
else
  fail "terraform version runs"
fi

# 3. Env loading
if [[ -f "$ROOT/.env" ]]; then
  # shellcheck source=build/load-env.sh
  source "$ROOT/build/load-env.sh"
  load_repo_env "$ROOT/build"
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    pass ".env loaded (AWS_ACCESS_KEY_ID set)"
  else
    fail ".env loaded"
  fi
else
  skip ".env not found — run ./setup-aws first"
fi

# 4. Terraform init + validate (no AWS needed for validate after init)
if "$TF" -chdir="$SMOKE_DIR" init -input=false >/dev/null 2>&1; then
  pass "terraform init (build/smoke)"
else
  fail "terraform init (build/smoke)"
fi

if "$TF" -chdir="$SMOKE_DIR" validate >/dev/null 2>&1; then
  pass "terraform validate (build/smoke)"
else
  fail "terraform validate (build/smoke)"
fi

# 5. Plan — needs valid AWS creds
if [[ -f "$ROOT/.env" ]]; then
  source "$ROOT/build/load-env.sh"
  load_repo_env "$ROOT/build"
  PLAN_OUT="$("$TF" -chdir="$SMOKE_DIR" plan -input=false 2>&1)" || true
  if echo "$PLAN_OUT" | grep -qE "account_id|Plan:|No changes"; then
    pass "terraform plan (build/smoke)"
  elif echo "$PLAN_OUT" | grep -qiE "InvalidClientTokenId|SignatureDoesNotMatch|UnrecognizedClientException|security token"; then
    skip "terraform plan — AWS 키가 유효하지 않음 (wrapper/env는 정상)"
  else
    fail "terraform plan (build/smoke)"
    echo "$PLAN_OUT" | tail -20
  fi
else
  skip "terraform plan — .env 없음"
fi

# 6. Cursor harness files
run_check "harness rule exists" test -f "$ROOT/.cursor/rules/harness-engineering.mdc"
run_check "hooks.json exists" test -f "$ROOT/.cursor/hooks.json"

echo
echo "=== result: pass=$PASS fail=$FAIL skip=$SKIP ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
