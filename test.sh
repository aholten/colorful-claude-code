#!/usr/bin/env bash
# test.sh — Test harness for claude-code-colorful-bash
# Run: ./test.sh [filter]
# Examples:
#   ./test.sh              # run all tests
#   ./test.sh parser       # run only parser tests
#   ./test.sh renderer     # run only renderer tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# --------------------------------------------------------------------------- #
#  Helpers                                                                      #
# --------------------------------------------------------------------------- #

assert_equals() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GREEN}[PASS]${RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} $test_name"
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
    echo -e "${GREEN}[PASS]${RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} $test_name"
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
    echo -e "${GREEN}[PASS]${RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} $test_name"
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
    echo -e "${GREEN}[PASS]${RESET} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} $test_name"
    echo "       not valid hook JSON: $(echo "$json" | cat -v)"
    FAIL=$((FAIL + 1))
  fi
}

should_run() {
  local section="$1"
  [[ -z "$FILTER" || "$section" == *"$FILTER"* ]]
}

# --------------------------------------------------------------------------- #
#  Source modules under test                                                    #
# --------------------------------------------------------------------------- #

source "$SCRIPT_DIR/scripts/parser.sh" 2>/dev/null || {
  echo -e "${YELLOW}[SKIP]${RESET} parser.sh not found — parser tests will fail"
}
source "$SCRIPT_DIR/scripts/renderer.sh" 2>/dev/null || {
  echo -e "${YELLOW}[SKIP]${RESET} renderer.sh not found — renderer tests will fail"
}

COMMAND_MAP="$SCRIPT_DIR/command-map.json"
HOOK_SCRIPT="$SCRIPT_DIR/scripts/annotate-pre.sh"

# =========================================================================== #
#  PARSER TESTS                                                                #
# =========================================================================== #

if should_run "parser"; then
  echo ""
  echo "=== Parser Tests ==="
  echo ""

  # --- Single commands ---

  result=$(parse_command "git status" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: single command - git status" \
    "CMD:git status" \
    "$result"

  result=$(parse_command "npm install" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: single command - npm install" \
    "CMD:npm install" \
    "$result"

  result=$(parse_command "ls -la /tmp" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: single command - ls with flags" \
    "CMD:ls -la /tmp" \
    "$result"

  # --- Compound commands with && ---

  result=$(parse_command "cd /foo && npm install" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:cd /foo
OP:&&
CMD:npm install"
  assert_equals "parser: compound - cd && npm install" \
    "$expected" \
    "$result"

  # --- Compound commands with || ---

  result=$(parse_command "make build || echo failed" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:make build
OP:||
CMD:echo failed"
  assert_equals "parser: compound - make || echo" \
    "$expected" \
    "$result"

  # --- Pipe ---

  result=$(parse_command "cat file.txt | grep error" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:cat file.txt
OP:|
CMD:grep error"
  assert_equals "parser: pipe - cat | grep" \
    "$expected" \
    "$result"

  # --- Semicolon ---

  result=$(parse_command "echo hello ; echo world" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo hello
OP:;
CMD:echo world"
  assert_equals "parser: semicolon - echo ; echo" \
    "$expected" \
    "$result"

  # --- Triple chain ---

  result=$(parse_command "cd /app && npm install && npm test" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:cd /app
OP:&&
CMD:npm install
OP:&&
CMD:npm test"
  assert_equals "parser: triple chain - cd && npm install && npm test" \
    "$expected" \
    "$result"

  # --- Mixed operators ---

  result=$(parse_command "make build && make test || echo fail" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:make build
OP:&&
CMD:make test
OP:||
CMD:echo fail"
  assert_equals "parser: mixed operators - && then ||" \
    "$expected" \
    "$result"

  # --- Command substitution ---

  result=$(parse_command 'echo $(date)' 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo
SUBCMD_START
CMD:date
SUBCMD_END"
  assert_equals "parser: command substitution - echo \$(date)" \
    "$expected" \
    "$result"

  # --- Nested command substitution ---

  result=$(parse_command 'echo $(cat $(find . -name foo))' 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo
SUBCMD_START
CMD:cat
SUBCMD_START
CMD:find . -name foo
SUBCMD_END
SUBCMD_END"
  assert_equals "parser: nested substitution - echo \$(cat \$(find))" \
    "$expected" \
    "$result"

  # --- Backtick substitution ---

  result=$(parse_command 'echo `date`' 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo
SUBCMD_START
CMD:date
SUBCMD_END"
  assert_equals "parser: backtick substitution - echo \`date\`" \
    "$expected" \
    "$result"

  # --- Subshell ---

  result=$(parse_command '(git add . && git commit -m "msg")' 2>/dev/null) || result="PARSE_ERROR"
  expected="SUBSHELL_START
CMD:git add .
OP:&&
CMD:git commit -m \"msg\"
SUBSHELL_END"
  assert_equals "parser: subshell - (git add && git commit)" \
    "$expected" \
    "$result"

  # --- Command substitution with operators inside ---

  result=$(parse_command 'echo $(cd /tmp && ls)' 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo
SUBCMD_START
CMD:cd /tmp
OP:&&
CMD:ls
SUBCMD_END"
  assert_equals "parser: substitution with inner operators" \
    "$expected" \
    "$result"

  # --- Empty command ---

  result=$(parse_command "" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: empty command" \
    "" \
    "$result"

  # --- Command with quoted strings containing operators ---

  result=$(parse_command 'echo "hello && world"' 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: quoted string with && inside" \
    'CMD:echo "hello && world"' \
    "$result"

  # --- Command with single quotes containing operators ---

  result=$(parse_command "echo 'hello && world'" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: single-quoted string with && inside" \
    "CMD:echo 'hello && world'" \
    "$result"

  # --- Multi-line commands ---

  input=$'echo hello\necho world'
  result=$(parse_multiline_command "$input" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:echo hello
NEWLINE
CMD:echo world"
  assert_equals "parser: multi-line produces NEWLINE token" \
    "$expected" \
    "$result"

  # --- Backslash continuation ---

  input=$'echo hello \\\nworld'
  result=$(parse_multiline_command "$input" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: backslash continuation joins lines" \
    "CMD:echo hello  world" \
    "$result"

  # --- Multi-line with operators ---

  input=$'cd /app && npm install\nnpm test'
  result=$(parse_multiline_command "$input" 2>/dev/null) || result="PARSE_ERROR"
  expected="CMD:cd /app
OP:&&
CMD:npm install
NEWLINE
CMD:npm test"
  assert_equals "parser: multi-line with operators" \
    "$expected" \
    "$result"

  # --- Single line still works via fast path ---

  result=$(parse_multiline_command "git status" 2>/dev/null) || result="PARSE_ERROR"
  assert_equals "parser: multiline func handles single line" \
    "CMD:git status" \
    "$result"

fi

# =========================================================================== #
#  MAPPING LOOKUP TESTS                                                        #
# =========================================================================== #

if should_run "mapping"; then
  echo ""
  echo "=== Mapping Lookup Tests ==="
  echo ""

  if [[ ! -f "$COMMAND_MAP" ]]; then
    echo -e "${YELLOW}[SKIP]${RESET} command-map.json not found — skipping mapping tests"
  else
    # Test that lookup_command function exists and works
    # lookup_command <base_command> should return: emoji bg_color fg_color

    result=$(lookup_command "git" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: git has emoji" "🔀" "$result"

    result=$(lookup_command "npm" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: npm has emoji" "📦" "$result"

    result=$(lookup_command "docker" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: docker has emoji" "🐳" "$result"

    result=$(lookup_command "python" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: python has emoji" "🐍" "$result"

    result=$(lookup_command "rm" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: rm has emoji" "🗑" "$result"

    result=$(lookup_command "cat" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_contains "mapping: cat has emoji" "🐱" "$result"

    # Unknown command returns default (no emoji, neutral colors)
    result=$(lookup_command "someunknowntool" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_not_contains "mapping: unknown command has no emoji" "LOOKUP_ERROR" "$result"
    assert_contains "mapping: unknown command returns _default" "_default" "$result"

    # Operator lookup
    result=$(lookup_operator "&&" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_not_contains "mapping: && operator resolves" "LOOKUP_ERROR" "$result"

    result=$(lookup_operator "||" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_not_contains "mapping: || operator resolves" "LOOKUP_ERROR" "$result"

    result=$(lookup_operator "|" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_not_contains "mapping: | operator resolves" "LOOKUP_ERROR" "$result"

    result=$(lookup_operator ";" 2>/dev/null) || result="LOOKUP_ERROR"
    assert_not_contains "mapping: ; operator resolves" "LOOKUP_ERROR" "$result"
  fi
fi

# =========================================================================== #
#  RENDERER TESTS                                                              #
# =========================================================================== #

if should_run "renderer"; then
  echo ""
  echo "=== Renderer Tests ==="
  echo ""

  # render_tokens takes token stream on stdin, outputs ANSI string
  # We use cat -v to make ANSI escapes visible for comparison

  # --- Known command gets emoji + brand colors ---

  tokens="CMD:git status"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  assert_contains "renderer: git gets emoji" "🔀" "$result"
  # Should contain ANSI escape sequences (ESC[)
  result_visible=$(echo "$tokens" | render_tokens 2>/dev/null | cat -v) || result_visible="RENDER_ERROR"
  assert_contains "renderer: git has ANSI escapes" "^[" "$result_visible"

  # --- Unknown command gets neutral bg, no emoji ---

  tokens="CMD:someunknowntool --flag"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  assert_contains "renderer: unknown cmd has command text" "someunknowntool" "$result"
  assert_not_contains "renderer: unknown cmd has no emoji" "🔀" "$result"

  # --- Operator gets its own emoji ---

  tokens="CMD:cd /foo
OP:&&
CMD:npm install"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  assert_contains "renderer: compound has cd text" "cd" "$result"
  assert_contains "renderer: compound has npm text" "npm" "$result"
  assert_contains "renderer: compound has && text" "&&" "$result"

  # --- No variation selector (plain Unicode emoji for OS rendering) ---

  tokens="CMD:git status"
  if command -v xxd >/dev/null 2>&1; then
    result=$(echo "$tokens" | render_tokens 2>/dev/null | xxd -p | tr -d '\n') || result="RENDER_ERROR"
  elif command -v od >/dev/null 2>&1; then
    result=$(echo "$tokens" | render_tokens 2>/dev/null | od -A n -t x1 | tr -d ' \n') || result="RENDER_ERROR"
  else
    result=""
  fi
  if [[ -n "$result" ]]; then
    # U+FE0F (EF B8 8F) should NOT be present — we use plain Unicode, no presentation selectors
    assert_not_contains "renderer: emoji has no variation selector (FE0F)" "efb88f" "$result"
  else
    echo -e "${YELLOW}[SKIP]${RESET} renderer: variation selector test (xxd/od not available)"
    SKIP=$((SKIP + 1))
  fi

  # --- Substitution markers rendered ---

  tokens="CMD:echo
SUBCMD_START
CMD:date
SUBCMD_END"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  assert_contains "renderer: substitution has echo" "echo" "$result"
  assert_contains "renderer: substitution has date" "date" "$result"
  # Should have $( and ) delimiters in output
  assert_contains "renderer: substitution has \$( delimiter" '$(' "$result"
  assert_contains "renderer: substitution has ) delimiter" ")" "$result"

  # --- Subshell markers rendered ---

  tokens="SUBSHELL_START
CMD:git add .
OP:&&
CMD:git commit
SUBSHELL_END"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  assert_contains "renderer: subshell has ( delimiter" "(" "$result"
  assert_contains "renderer: subshell has ) delimiter" ")" "$result"

  # --- ANSI reset at end ---

  tokens="CMD:git status"
  result_visible=$(echo "$tokens" | render_tokens 2>/dev/null | cat -v) || result_visible="RENDER_ERROR"
  # Should end with reset code ESC[0m
  assert_contains "renderer: output ends with ANSI reset" "[0m" "$result_visible"

  # --- Erase-to-EOL at end (prevents background bleed) ---

  tokens="CMD:git status"
  result_visible=$(echo "$tokens" | render_tokens 2>/dev/null | cat -v) || result_visible="RENDER_ERROR"
  # Should end with ESC[K (erase to end of line) after reset
  assert_contains "renderer: output ends with erase-to-EOL" "[K" "$result_visible"

  # --- Multi-line rendering ---

  tokens="CMD:echo hello
NEWLINE
CMD:echo world"
  result=$(echo "$tokens" | render_tokens 2>/dev/null) || result="RENDER_ERROR"
  # Output should contain a literal newline
  line_count=$(echo "$result" | wc -l)
  if [[ "$line_count" -ge 2 ]]; then
    echo -e "${GREEN}[PASS]${RESET} renderer: multi-line output has multiple lines"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${RESET} renderer: multi-line output has multiple lines"
    echo "       expected >= 2 lines, got: $line_count"
    FAIL=$((FAIL + 1))
  fi

  # Each line before NEWLINE should have reset+erase
  result_visible=$(echo "$tokens" | render_tokens 2>/dev/null | cat -v) || result_visible="RENDER_ERROR"
  first_line=$(echo "$result_visible" | head -1)
  assert_contains "renderer: multi-line first line has erase-to-EOL" "[K" "$first_line"

fi

# =========================================================================== #
#  HOOK I/O TESTS (Integration)                                                #
# =========================================================================== #

if should_run "hook"; then
  echo ""
  echo "=== Hook I/O Tests ==="
  echo ""

  if [[ ! -x "$HOOK_SCRIPT" ]]; then
    echo -e "${YELLOW}[SKIP]${RESET} annotate-pre.sh not found or not executable — skipping hook tests"
  else

    # --- Valid Bash tool input ---

    input='{"tool_name":"Bash","input":{"command":"git status"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: valid Bash tool returns JSON" "$result"
    assert_contains "hook: output contains systemMessage" '"systemMessage"' "$result"

    # --- Non-Bash tool should pass through (no annotation) ---

    input='{"tool_name":"Read","input":{"file_path":"/tmp/foo"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    # Should return empty or a no-op response
    assert_not_contains "hook: non-Bash tool not annotated" "systemMessage" "$result"

    # --- Compound command ---

    input='{"tool_name":"Bash","input":{"command":"cd /app && npm install"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: compound command returns valid JSON" "$result"

    # --- Command substitution ---

    input='{"tool_name":"Bash","input":{"command":"echo $(date)"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: substitution returns valid JSON" "$result"

    # --- Empty command ---

    input='{"tool_name":"Bash","input":{"command":""}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    # Should handle gracefully — either empty response or valid JSON
    if [[ -n "$result" ]]; then
      assert_json_valid "hook: empty command returns valid JSON if non-empty" "$result"
    else
      echo -e "${GREEN}[PASS]${RESET} hook: empty command returns empty (no-op)"
      PASS=$((PASS + 1))
    fi

    # --- JSON escaping: output should not break JSON ---

    input='{"tool_name":"Bash","input":{"command":"echo \"hello world\""}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: quoted args produce valid JSON" "$result"

    # --- Command with special characters ---

    input='{"tool_name":"Bash","input":{"command":"grep -r \"pattern\" /tmp/*.log"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: special chars produce valid JSON" "$result"

    # --- Output is simple {"systemMessage": "..."} with no extra fields ---

    input='{"tool_name":"Bash","input":{"command":"git status"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_not_contains "hook: no hookSpecificOutput in output" '"hookSpecificOutput"' "$result"

    # --- Multi-line command (newline encoded as \n in JSON) ---

    input='{"tool_name":"Bash","input":{"command":"echo hello\necho world"}}'
    result=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null) || result="HOOK_ERROR"
    assert_json_valid "hook: multi-line command returns valid JSON" "$result"
    # The systemMessage should contain literal \n (escaped newline) in the JSON
    assert_contains "hook: multi-line output has newline escape" '\n' "$result"

  fi
fi

# =========================================================================== #
#  Summary                                                                      #
# =========================================================================== #

echo ""
echo "==========================================="
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET} out of ${TOTAL} tests"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
