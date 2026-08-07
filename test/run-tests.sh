#!/usr/bin/env bash
# ai-relay test suite. No external test framework: bash + jq only.
# Usage: ./test/run-tests.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
pass() { printf 'ok  : %s\n' "$1"; PASS=$((PASS + 1)); }

# assert_argv_seq <log> <message> <arg>...
# Asserts the given args appear in the log in this exact order (gaps allowed).
assert_argv_seq() {
  local log="$1"; shift
  local msg="$1"; shift
  local line idx=0
  local -a wanted
  wanted=("$@")
  while IFS= read -r line; do
    if [ "$idx" -lt "${#wanted[@]}" ] && [ "$line" = "${wanted[$idx]}" ]; then
      idx=$((idx + 1))
    fi
  done < "$log"
  if [ "$idx" -eq "${#wanted[@]}" ]; then
    pass "$msg"
  else
    fail "$msg (matched $idx/${#wanted[@]}; log below)"
    sed 's/^/      /' "$log" >&2
  fi
}

assert_contains() {
  local file="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" "$file"; then pass "$msg"; else
    fail "$msg (missing: $needle)"
    sed 's/^/      /' "$file" >&2
  fi
}

assert_file_is() {
  local file="$1" expected="$2" msg="$3"
  local actual
  actual="$(cat "$file" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then pass "$msg"; else
    fail "$msg (expected '$expected', got '$actual')"
  fi
}

# make_sandbox — creates an isolated project dir + AI_RELAY_HOME, echoes the dir
make_sandbox() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/project" "$dir/home/presets"
  cp "$REPO_ROOT/relay-run.sh" "$dir/relay-run.sh"
  chmod +x "$dir/relay-run.sh"
  cat > "$dir/home/presets/fake.json" <<EOF
{
  "cli": "$REPO_ROOT/test/fixtures/fake-cli",
  "flags": { "pre": "", "model": "-m", "prompt": "-p", "continue": "-c", "session": "-s", "workdir": "" }
}
EOF
  cat > "$dir/home/presets/fake-sub.json" <<EOF
{
  "cli": "$REPO_ROOT/test/fixtures/fake-cli",
  "flags": { "pre": "run", "model": "-m", "prompt": "--auto", "continue": "-c", "session": "-s", "workdir": "--dir" }
}
EOF
  printf '%s' "$dir"
}

# --- Test 1: v3 target resolution puts the model flag before the prompt flags
t1() {
  local dir; dir="$(make_sandbox)"
  cat > "$dir/project/.ai-relay.json" <<'EOF'
{
  "version": 3,
  "targets": { "cc-glm": { "preset": "fake", "model": "zai-org/glm-5.2" } },
  "default_target": "cc-glm",
  "status_file": ".relay_status"
}
EOF
  ( cd "$dir/project" \
    && AI_RELAY_HOME="$dir/home" FAKE_CLI_LOG="$dir/argv.log" \
       "$dir/relay-run.sh" --target cc-glm "do the thing" >/dev/null 2>&1 )
  assert_argv_seq "$dir/argv.log" "v3: model flag precedes prompt flag" \
    "-m" "zai-org/glm-5.2" "-p" "do the thing"
  assert_file_is "$dir/project/.relay_status" "DONE" "v3: status file is DONE"
  rm -rf "$dir"
}

# --- Test 2: subcommand-style preset keeps `pre` first and appends workdir
t2() {
  local dir; dir="$(make_sandbox)"
  cat > "$dir/project/.ai-relay.json" <<'EOF'
{
  "version": 3,
  "targets": { "oc-kimi": { "preset": "fake-sub", "model": "opencode-go/kimi-k2.7-code" } },
  "default_target": "oc-kimi",
  "status_file": ".relay_status"
}
EOF
  ( cd "$dir/project" \
    && AI_RELAY_HOME="$dir/home" FAKE_CLI_LOG="$dir/argv.log" \
       "$dir/relay-run.sh" --target oc-kimi "build it" >/dev/null 2>&1 )
  assert_argv_seq "$dir/argv.log" "v3: subcommand preset ordering" \
    "run" "-m" "opencode-go/kimi-k2.7-code" "--auto" "build it" "--dir"
  rm -rf "$dir"
}

# --- Test 3: unknown target fails and lists what is available
t3() {
  local dir; dir="$(make_sandbox)"
  cat > "$dir/project/.ai-relay.json" <<'EOF'
{
  "version": 3,
  "targets": { "cc-glm": { "preset": "fake", "model": "zai-org/glm-5.2" } },
  "default_target": "cc-glm",
  "status_file": ".relay_status"
}
EOF
  local out rc
  out="$( cd "$dir/project" && AI_RELAY_HOME="$dir/home" FAKE_CLI_LOG="$dir/argv.log" \
          "$dir/relay-run.sh" --target nope "x" 2>&1 )"; rc=$?
  if [ "$rc" -ne 0 ]; then pass "v3: unknown target exits non-zero"; else fail "v3: unknown target exits non-zero"; fi
  printf '%s\n' "$out" > "$dir/err.log"
  assert_contains "$dir/err.log" "cc-glm" "v3: unknown target lists available targets"
  rm -rf "$dir"
}

# --- Test 4: v2 config (no version) produces the exact v2 command line
t4() {
  local dir; dir="$(make_sandbox)"
  cat > "$dir/project/.ai-relay.json" <<EOF
{
  "cli": "$REPO_ROOT/test/fixtures/fake-cli",
  "flags": { "prompt": "--print -p", "continue": "-C", "session": "-S", "workdir": "-w" },
  "max_retries": 3,
  "status_file": ".relay_status"
}
EOF
  ( cd "$dir/project" \
    && AI_RELAY_HOME="$dir/home" FAKE_CLI_LOG="$dir/argv.log" \
       "$dir/relay-run.sh" "legacy task" >/dev/null 2>&1 )
  assert_argv_seq "$dir/argv.log" "v2: legacy config still works unchanged" \
    "--print" "-p" "legacy task" "-w"
  if grep -qxF -- "-m" "$dir/argv.log"; then
    fail "v2: no model flag injected"
  else
    pass "v2: no model flag injected"
  fi
  rm -rf "$dir"
}

# --- Test 5: --continue appends the continue flag; failure writes FAILED
t5() {
  local dir; dir="$(make_sandbox)"
  cat > "$dir/project/.ai-relay.json" <<'EOF'
{
  "version": 3,
  "targets": { "cc-glm": { "preset": "fake", "model": "m1" } },
  "default_target": "cc-glm",
  "status_file": ".relay_status"
}
EOF
  ( cd "$dir/project" \
    && AI_RELAY_HOME="$dir/home" FAKE_CLI_LOG="$dir/argv.log" FAKE_CLI_EXIT=1 \
       "$dir/relay-run.sh" --target cc-glm "fix it" --continue >/dev/null 2>&1 )
  assert_argv_seq "$dir/argv.log" "v3: --continue appends continue flag" \
    "-p" "fix it" "-c"
  assert_file_is "$dir/project/.relay_status" "FAILED" "v3: non-zero exit writes FAILED"
  rm -rf "$dir"
}

# --- Test 6: every preset declares the full flag schema
t6() {
  local f name missing
  for f in "$REPO_ROOT"/presets/*.json; do
    name="$(basename "$f" .json)"
    if ! jq -e '.cli' "$f" >/dev/null 2>&1; then
      fail "preset $name: missing .cli"; continue
    fi
    missing="$(jq -r '
      ["pre","model","prompt","continue","session","workdir"]
      - (.flags // {} | keys) | join(",")' "$f")"
    if [ -n "$missing" ]; then
      fail "preset $name: missing flag keys: $missing"
    else
      pass "preset $name: full flag schema"
    fi
  done
}

# --- Test 7: install.sh populates AI_RELAY_HOME and does not gitignore config
t7() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/project"
  ( cd "$dir/project" \
    && git init -q . \
    && printf '.ai-relay.json\n.relay_status\n' > .gitignore \
    && AI_RELAY_HOME="$dir/home" CLAUDE_HOME="$dir/claude" \
       "$REPO_ROOT/install.sh" commandcode >/dev/null 2>&1 )

  if [ -x "$dir/home/relay-run.sh" ]; then pass "install: runner is global and executable"
  else fail "install: runner is global and executable"; fi

  if [ -f "$dir/home/presets/opencode.json" ]; then pass "install: presets copied to AI_RELAY_HOME"
  else fail "install: presets copied to AI_RELAY_HOME"; fi

  if [ -f "$dir/project/.ai-relay.json" ]; then pass "install: project config created"
  else fail "install: project config created"; fi

  if grep -qxF '.ai-relay.json' "$dir/project/.gitignore"; then
    fail "install: removes .ai-relay.json from .gitignore"
  else
    pass "install: removes .ai-relay.json from .gitignore"
  fi

  if grep -qxF '.relay_status' "$dir/project/.gitignore"; then
    pass "install: keeps .relay_status ignored"
  else fail "install: keeps .relay_status ignored"; fi

  if [ -f "$dir/project/relay-run.sh" ]; then
    fail "install: does not drop a runner into the project"
  else
    pass "install: does not drop a runner into the project"
  fi
  rm -rf "$dir"
}

t1; t2; t3; t4; t5; t6; t7

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
