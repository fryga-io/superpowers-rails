#!/usr/bin/env bash
# Integration Test: executing-plans (Native) on a superpowers-rails slice plan
#
# The fork's writing-plans writes `### Slice N:` units with no `Expected:`
# lines, Interfaces blocks, or commit steps; upstream's Native executor was
# written for step-level `Task N` plans. This test runs Native execution on a
# slice plan and asserts:
#   - task-start extracts every slice (no "task N not found")
#   - task-done ledgers every slice with a non-empty commit range
#   - one commit per slice lands in git
#   - the final whole-branch review is dispatched
#   - the implementation works
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Integration Test: executing-plans on a slice plan"
echo "========================================"
echo ""
echo "WARNING: This test may take 5-20 minutes to complete."
echo ""

TEST_PROJECT=$(create_test_project)
echo "Test project: $TEST_PROJECT"
trap "cleanup_test_project $TEST_PROJECT" EXIT

cd "$TEST_PROJECT"

cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF

mkdir -p src test docs/superpowers/plans

cat > docs/superpowers/plans/slice-plan.md <<'EOF'
# Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-rails:subagent-driven-development (recommended) or superpowers-rails:executing-plans. Each slice below is one unit of work — implement them in order, one subagent per slice. Slices use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A caller can add and multiply two numbers through `src/math.js`.

**Architecture:** One ES module exporting pure functions, tested with `node --test`.

**Spec:** none — this plan is its own spec.

## Global Constraints

- No dependencies beyond Node's standard library.
- Export only the functions named in the slices.

## Review Focus

- Negative operands: `add(-1, 1)` is `0`, `multiply(-2, 3)` is `-6`.

---

### Slice 1: A caller can add two numbers

- [ ] **Delivers:** `add(a, b)` exported from `src/math.js`, returning the sum.
- [ ] **Touches:** `src/math.js`, `test/math.test.js`
- [ ] **End-to-end test (write first, watch it fail, then build the slice to green):**
  `test/math.test.js` asserts `add(2, 3) === 5`, `add(0, 0) === 0`, `add(-1, 1) === 0`. Run with `npm test`.
- [ ] **Notes:** None.

### Slice 2: A caller can multiply two numbers

- [ ] **Delivers:** `multiply(a, b)` exported from `src/math.js`, returning the product. No other operations.
- [ ] **Touches:** `src/math.js`, `test/math.test.js`
- [ ] **End-to-end test (write first, watch it fail, then build the slice to green):**
  `test/math.test.js` asserts `multiply(2, 3) === 6`, `multiply(0, 5) === 0`, `multiply(-2, 3) === -6`. Run with `npm test`.
- [ ] **Notes:** None.
EOF

git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial commit" --quiet
BASE_SHA=$(git rev-parse HEAD)
git checkout -q -b feature/calculator

PROMPT="Execute the implementation plan at docs/superpowers/plans/slice-plan.md inline in this session using the superpowers-rails:executing-plans skill (Native execution). I have already chosen Native execution. You are on the feature branch feature/calculator; work here. Begin now."

PLUGIN_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
OUTPUT_FILE="$TEST_PROJECT/claude-output.txt"

echo "Running Claude (plugin-dir: $PLUGIN_DIR, cwd: $TEST_PROJECT)..."
echo "================================================================================"
cd "$TEST_PROJECT" && timeout 1800 claude -p "$PROMPT" --plugin-dir "$PLUGIN_DIR" --allowed-tools=all --permission-mode bypassPermissions 2>&1 | tee "$OUTPUT_FILE" || {
    echo ""
    echo "================================================================================"
    echo "EXECUTION FAILED (exit code: $?)"
    exit 1
}
echo "================================================================================"
echo ""

TEST_PROJECT_REAL=$(cd "$TEST_PROJECT" && pwd -P)
SESSION_DIR="$HOME/.claude/projects/$(echo "$TEST_PROJECT_REAL" | sed 's|[^a-zA-Z0-9]|-|g')"
SESSION_FILE=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 || true)
if [ -z "$SESSION_FILE" ]; then
    echo "ERROR: Could not find session transcript file"
    echo "Looked in: $SESSION_DIR"
    exit 1
fi
echo "Analyzing session transcript: $(basename "$SESSION_FILE")"
echo ""

FAILED=0
echo "=== Verification Tests ==="
echo ""

echo "Test 1: executing-plans skill invoked..."
if grep -q '"name":"Skill".*"skill":"superpowers-rails:executing-plans"' "$SESSION_FILE"; then
    echo "  [PASS] executing-plans skill was invoked"
else
    echo "  [FAIL] executing-plans skill was not invoked"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 2: task-start extracted every slice..."
if grep -q 'not found in .*slice-plan.md' "$SESSION_FILE"; then
    echo "  [FAIL] task-start/task-brief reported a slice as not found"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] no 'task N not found' errors"
fi
echo ""

echo "Test 3: task-done ledgered every slice with a non-empty commit range..."
ledger_lines=$(grep -oE 'ledger: Task [0-9]+: complete \(commits [0-9a-f]+\.\.[0-9a-f]+' "$SESSION_FILE" | sort -u || true)
for n in 1 2; do
    line=$(printf '%s\n' "$ledger_lines" | grep "Task $n:" | head -1 || true)
    if [ -z "$line" ]; then
        echo "  [FAIL] no task-done ledger line for slice $n"
        FAILED=$((FAILED + 1))
        continue
    fi
    range=${line##*commits }
    if [ "${range%%..*}" != "${range##*..}" ]; then
        echo "  [PASS] slice $n ledgered with commits $range"
    else
        echo "  [FAIL] slice $n ledgered with an empty range ($range) — work not committed"
        FAILED=$((FAILED + 1))
    fi
done
echo ""

echo "Test 4: one commit per slice..."
commit_count=$(git -C "$TEST_PROJECT" rev-list --count "$BASE_SHA"..HEAD 2>/dev/null || echo 0)
if [ "$commit_count" -ge 2 ]; then
    echo "  [PASS] $commit_count commits on the feature branch"
else
    echo "  [FAIL] $commit_count commit(s) on the feature branch (expected >= 2)"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 5: final whole-branch review dispatched..."
review_count=$(grep -cE '"name":"(Agent|Task)"' "$SESSION_FILE" || true)
if [ "${review_count:-0}" -ge 1 ]; then
    echo "  [PASS] $review_count subagent dispatch(es)"
else
    echo "  [FAIL] no reviewer subagent dispatched"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 6: implementation works..."
if grep -q "export function add" "$TEST_PROJECT/src/math.js" 2>/dev/null \
    && grep -q "export function multiply" "$TEST_PROJECT/src/math.js" 2>/dev/null; then
    echo "  [PASS] add and multiply exported"
else
    echo "  [FAIL] add/multiply missing from src/math.js"
    FAILED=$((FAILED + 1))
fi
if (cd "$TEST_PROJECT" && npm test > test-output.txt 2>&1); then
    echo "  [PASS] npm test passes"
else
    echo "  [FAIL] npm test fails"
    cat "$TEST_PROJECT/test-output.txt"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "========================================"
if [ "$FAILED" -eq 0 ]; then
    echo "STATUS: PASSED"
else
    echo "STATUS: FAILED"
    echo "Failed $FAILED verification tests"
fi
echo "========================================"
[ "$FAILED" -eq 0 ]
