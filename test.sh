#!/usr/bin/env bash
# test.sh — Test harness for colorful-claude-code
# Run: ./test.sh [filter]
# Examples:
#   ./test.sh              # run all tests
#   ./test.sh parser       # run only segmentation tests
#   ./test.sh renderer     # run only renderer tests
#   ./test.sh mapping      # run only emoji/color lookup tests
#   ./test.sh hook         # run only hook I/O tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# --------------------------------------------------------------------------- #
#  Source the module under test                                                #
# --------------------------------------------------------------------------- #
# annotate-pre.sh only runs its main entry point when executed directly, so
# sourcing exposes _lookup, _lookup_op, render_command, _render_segment, and
# the JSON helpers for unit testing.

source "$SCRIPT_DIR/scripts/annotate-pre.sh"

HOOK_SCRIPT="$SCRIPT_DIR/scripts/annotate-pre.sh"

# Test-output colors (defined after sourcing — the hook defines its own RESET)
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

# --------------------------------------------------------------------------- #
#  Helpers                                                                      #
# --------------------------------------------------------------------------- #

assert_equals() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} $test_name"
    echo "       expected: $(echo "$expected" | cat -v)"
    echo "       actual:   $(echo "$actual" | cat -v)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} $test_name"
    echo "       expected to contain: $needle"
    echo "       actual: $(echo "$haystack" | cat -v)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} $test_name"
    echo "       expected NOT to contain: $needle"
    echo "       actual: $(echo "$haystack" | cat -v)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_valid() {
  local test_name="$1"
  local json="$2"

  # Basic JSON validation: starts with { and ends with }, has "systemMessage"
  if [[ "$json" == "{"* && "$json" == *"}" && "$json" == *'"systemMessage"'* ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} $test_name"
    echo "       not valid hook JSON: $(echo "$json" | cat -v)"
    FAIL=$((FAIL + 1))
  fi
}

should_run() {
  local section="$1"
  [[ -z "$FILTER" || "$section" == *"$FILTER"* ]]
}

# Strip ANSI color/erase sequences so assertions see only text + emoji
strip_ansi() {
  sed -e $'s/\033\\[[0-9;]*[mK]//g'
}

# render_command output with ANSI removed
plain() {
  render_command "$1" | strip_ansi
}

# Count non-overlapping occurrences of a substring (pure bash — avoids
# locale-dependent grep behavior on multibyte emoji)
count_occurrences() {
  local s="$1" needle="$2" n=0
  while [[ "$s" == *"$needle"* ]]; do
    s="${s#*"$needle"}"
    n=$((n + 1))
  done
  echo "$n"
}

# =========================================================================== #
#  SEGMENTATION TESTS (parser)                                                 #
# =========================================================================== #
# Operator splitting, quote/substitution tracking, and wrapper unwrapping all
# live inside render_command/_render_segment.

if should_run "parser"; then
  echo ""
  echo "=== Segmentation Tests ==="
  echo ""

  # --- Single commands ---

  result=$(plain "git status")
  assert_contains "parser: single command keeps text" "git status" "$result"
  assert_contains "parser: single command gets brand emoji" "🔀" "$result"

  # --- Compound commands with && ---

  result=$(plain "cd /foo && npm install")
  assert_contains "parser: compound keeps first segment" "cd /foo" "$result"
  assert_contains "parser: compound keeps second segment" "npm install" "$result"
  assert_contains "parser: compound keeps && text" "&&" "$result"
  assert_contains "parser: && gets operator emoji" "✅" "$result"
  assert_contains "parser: cd segment gets emoji" "📁" "$result"
  assert_contains "parser: npm segment gets emoji" "📦" "$result"

  # --- || operator ---

  result=$(plain "make build || echo failed")
  assert_contains "parser: || keeps text" "||" "$result"
  assert_contains "parser: || gets operator emoji" "⚠" "$result"

  # --- Pipe ---

  result=$(plain "cat file.txt | grep error")
  assert_contains "parser: pipe gets operator emoji" "🔗" "$result"
  assert_contains "parser: cat segment gets emoji" "🐱" "$result"
  assert_contains "parser: grep segment gets emoji" "🔍" "$result"

  # --- Semicolon ---

  result=$(plain "echo hello ; echo world")
  assert_contains "parser: semicolon gets operator emoji" "⏩" "$result"

  # --- Triple chain: exactly two && operators ---

  result=$(plain "cd /app && npm install && npm test")
  assert_equals "parser: triple chain renders two && operators" \
    "2" "$(count_occurrences "$result" "✅")"
  assert_contains "parser: triple chain keeps last segment" "npm test" "$result"

  # --- Mixed operators ---

  result=$(plain "make build && make test || echo fail")
  assert_contains "parser: mixed has && emoji" "✅" "$result"
  assert_contains "parser: mixed has || emoji" "⚠" "$result"

  # --- Quoted strings containing operators are NOT split ---

  result=$(plain 'echo "hello && world"')
  assert_not_contains "parser: double-quoted && not treated as operator" "✅" "$result"
  assert_contains "parser: double-quoted text preserved" 'hello && world' "$result"

  result=$(plain "echo 'hello && world'")
  assert_not_contains "parser: single-quoted && not treated as operator" "✅" "$result"
  assert_contains "parser: single-quoted text preserved" "hello && world" "$result"

  # --- Command substitution stays inside its segment ---

  result=$(plain 'echo $(cd /tmp && ls)')
  assert_not_contains "parser: && inside \$() not treated as operator" "✅" "$result"
  assert_contains "parser: substitution text preserved" '$(cd /tmp && ls)' "$result"

  result=$(plain 'echo `date`')
  assert_contains "parser: backtick substitution preserved" '`date`' "$result"
  assert_contains "parser: backtick segment gets echo emoji" "💬" "$result"

  # --- Subshell stays one segment ---

  result=$(plain '(git add . && git commit -m "msg")')
  assert_not_contains "parser: && inside subshell not treated as operator" "✅" "$result"
  assert_contains "parser: subshell text preserved" "git add ." "$result"

  # --- Wrapper unwrapping finds the real command ---

  result=$(plain "sudo rm -rf /tmp/x")
  assert_contains "parser: sudo unwraps to rm emoji" "🗑" "$result"

  result=$(plain "bash -c 'git status'")
  assert_contains "parser: bash -c unwraps to git emoji" "🔀" "$result"

  result=$(plain "env CI=1 npm test")
  assert_contains "parser: env prefix unwraps to npm emoji" "📦" "$result"

  # --- Empty command ---

  result=$(plain "")
  assert_equals "parser: empty command renders nothing" "" "$result"

fi

# =========================================================================== #
#  MAPPING LOOKUP TESTS                                                        #
# =========================================================================== #
# The live mappings are the _lookup/_lookup_op tables in annotate-pre.sh.

if should_run "mapping"; then
  echo ""
  echo "=== Mapping Lookup Tests ==="
  echo ""

  result=$(_lookup "git")
  assert_contains "mapping: git has emoji" "🔀" "$result"
  assert_contains "mapping: git has brand colors" "214 16" "$result"

  result=$(_lookup "npm")
  assert_contains "mapping: npm has emoji" "📦" "$result"
  assert_contains "mapping: npm has brand colors" "175 16" "$result"

  result=$(_lookup "docker")
  assert_contains "mapping: docker has emoji" "🐳" "$result"

  result=$(_lookup "python")
  assert_contains "mapping: python has emoji" "🐍" "$result"

  result=$(_lookup "rm")
  assert_contains "mapping: rm has emoji" "🗑" "$result"
  assert_contains "mapping: rm has danger colors" "160 230" "$result"

  result=$(_lookup "cat")
  assert_contains "mapping: cat has emoji" "🐱" "$result"

  # Unknown command returns the default (no emoji, neutral colors)
  result=$(_lookup "someunknowntool")
  assert_equals "mapping: unknown command returns default" "_ 240 255" "$result"

  # Operator lookup
  result=$(_lookup_op "&&")
  assert_contains "mapping: && operator resolves" "✅" "$result"

  result=$(_lookup_op "||")
  assert_contains "mapping: || operator resolves" "⚠" "$result"

  result=$(_lookup_op "|")
  assert_contains "mapping: | operator resolves" "🔗" "$result"

  result=$(_lookup_op ";")
  assert_contains "mapping: ; operator resolves" "⏩" "$result"

  result=$(_lookup_op "&")
  assert_equals "mapping: unknown operator returns default" "_ 236 250" "$result"

fi

# =========================================================================== #
#  RENDERER TESTS                                                              #
# =========================================================================== #

if should_run "renderer"; then
  echo ""
  echo "=== Renderer Tests ==="
  echo ""

  # --- Known command gets emoji + brand colors ---

  result=$(render_command "git status")
  assert_contains "renderer: git gets emoji" "🔀" "$result"

  result_visible=$(printf '%s' "$result" | cat -v)
  assert_contains "renderer: git has ANSI escapes" "^[" "$result_visible"
  assert_contains "renderer: git uses brand bg color" "48;5;214" "$result_visible"

  # --- Unknown command gets neutral bg, no emoji ---

  result=$(render_command "someunknowntool --flag")
  assert_contains "renderer: unknown cmd has command text" "someunknowntool" "$result"
  assert_not_contains "renderer: unknown cmd has no emoji" "🔀" "$result"
  result_visible=$(printf '%s' "$result" | cat -v)
  assert_contains "renderer: unknown cmd uses neutral bg" "48;5;240" "$result_visible"

  # --- ANSI reset + erase-to-EOL at end (prevents background bleed) ---

  result_visible=$(printf '%s' "$(render_command "git status")" | cat -v)
  assert_contains "renderer: output contains ANSI reset" "[0m" "$result_visible"
  if [[ "$result_visible" == *'[K' ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} renderer: output ends with erase-to-EOL"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} renderer: output ends with erase-to-EOL"
    echo "       actual end: ${result_visible: -20}"
    FAIL=$((FAIL + 1))
  fi

  # --- No variation selector (plain Unicode emoji for OS rendering) ---

  if command -v xxd >/dev/null 2>&1; then
    result=$(render_command "git status" | xxd -p | tr -d '\n')
  elif command -v od >/dev/null 2>&1; then
    result=$(render_command "git status" | od -A n -t x1 | tr -d ' \n')
  else
    result=""
  fi
  if [[ -n "$result" ]]; then
    # U+FE0F (EF B8 8F) should NOT be present — plain Unicode, no presentation selectors
    assert_not_contains "renderer: emoji has no variation selector (FE0F)" "efb88f" "$result"
  else
    echo -e "${C_YELLOW}[SKIP]${C_RESET} renderer: variation selector test (xxd/od not available)"
    SKIP=$((SKIP + 1))
  fi

  # --- Operators render on their own visual line ---

  result=$(render_command "cd /a && ls")
  line_count=$(printf '%s\n' "$result" | wc -l)
  if [[ "$line_count" -ge 3 ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} renderer: operator gets its own line"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} renderer: operator gets its own line"
    echo "       expected >= 3 lines, got: $line_count"
    FAIL=$((FAIL + 1))
  fi

  # --- Long segments are chunked into multiple styled lines ---

  longword=$(printf 'a%.0s' {1..150})
  result=$(render_command "echo $longword")
  line_count=$(printf '%s\n' "$result" | wc -l)
  if [[ "$line_count" -ge 2 ]]; then
    echo -e "${C_GREEN}[PASS]${C_RESET} renderer: long segment chunks into multiple lines"
    PASS=$((PASS + 1))
  else
    echo -e "${C_RED}[FAIL]${C_RESET} renderer: long segment chunks into multiple lines"
    echo "       expected >= 2 lines, got: $line_count"
    FAIL=$((FAIL + 1))
  fi

  # Each chunked line carries its own styled span (reset on every line)
  result_visible=$(printf '%s' "$result" | cat -v)
  first_line=$(printf '%s\n' "$result_visible" | head -1)
  assert_contains "renderer: first chunk line is a closed span" "[0m" "$first_line"

fi

# =========================================================================== #
#  HOOK I/O TESTS (Integration)                                                #
# =========================================================================== #

if should_run "hook"; then
  echo ""
  echo "=== Hook I/O Tests ==="
  echo ""

  if [[ ! -f "$HOOK_SCRIPT" ]]; then
    echo -e "${C_YELLOW}[SKIP]${C_RESET} annotate-pre.sh not found — skipping hook tests"
  else

    # --- Valid Bash tool input (real PreToolUse shape: tool_input) ---

    input='{"session_id":"t","tool_name":"Bash","tool_input":{"command":"git status"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: valid Bash tool returns JSON" "$result"
    assert_contains "hook: output contains systemMessage" '"systemMessage"' "$result"

    # --- Legacy/alternate input key still annotated ---

    input='{"tool_name":"Bash","input":{"command":"git status"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: legacy input key still annotated" "$result"

    # --- Non-Bash tool should pass through (no annotation) ---

    input='{"session_id":"t","tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_not_contains "hook: non-Bash tool not annotated" "systemMessage" "$result"

    # --- Compound command: operators produce escaped newlines ---

    input='{"tool_name":"Bash","tool_input":{"command":"cd /app && npm install"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: compound command returns valid JSON" "$result"
    assert_contains "hook: compound command has newline escapes" '\n' "$result"

    # --- Command substitution ---

    input='{"tool_name":"Bash","tool_input":{"command":"echo $(date)"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: substitution returns valid JSON" "$result"

    # --- Empty command ---

    input='{"tool_name":"Bash","tool_input":{"command":""}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    # Should handle gracefully — either empty response or valid JSON
    if [[ -n "$result" ]]; then
      assert_json_valid "hook: empty command returns valid JSON if non-empty" "$result"
    else
      echo -e "${C_GREEN}[PASS]${C_RESET} hook: empty command returns empty (no-op)"
      PASS=$((PASS + 1))
    fi

    # --- JSON escaping: output should not break JSON ---

    input='{"tool_name":"Bash","tool_input":{"command":"echo \"hello world\""}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: quoted args produce valid JSON" "$result"

    # --- Command with special characters ---

    input='{"tool_name":"Bash","tool_input":{"command":"grep -r \"pattern\" /tmp/*.log"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: special chars produce valid JSON" "$result"

    # --- Output is simple {"systemMessage": "..."} with no extra fields ---

    input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_not_contains "hook: no hookSpecificOutput in output" '"hookSpecificOutput"' "$result"

    # --- Multi-line command collapses to one annotated line ---
    # The hook deliberately flattens newlines so the annotation stays compact;
    # the executed command is unaffected.

    input='{"tool_name":"Bash","tool_input":{"command":"echo hello\necho world"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: multi-line command returns valid JSON" "$result"
    assert_contains "hook: multi-line command collapsed to one segment" "echo hello echo world" "$result"
    assert_not_contains "hook: collapsed command has no newline escapes" '\n' "$result"

  fi
fi

# =========================================================================== #
#  Summary                                                                      #
# =========================================================================== #

echo ""
echo "==========================================="
TOTAL=$((PASS + FAIL))
echo -e "Results: ${C_GREEN}${PASS} passed${C_RESET}, ${C_RED}${FAIL} failed${C_RESET} out of ${TOTAL} tests"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
