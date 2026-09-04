#!/usr/bin/env bash
# Integration Test: the Rails stage of requesting-code-review
#
# The fork used to ship this as a `/codereview` slash command, which only ran
# when someone typed it. It now lives in skills/requesting-code-review, so the
# observable is behavioral: asked for a review inside a Rails project, does the
# agent plan the Rails conventions stage and local CI — not just a generic
# code review?
#
# Falsifiability: delete the "Rails Projects - MANDATORY" section from
# skills/requesting-code-review/SKILL.md and this test fails. A run in a
# non-Rails project must NOT plan the Rails stage, which is what the second
# assertion pins down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Integration Test: review Rails stage"
echo "========================================"
echo ""

TEST_PROJECT=$(create_test_project)
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
cd "$TEST_PROJECT"

mkdir -p app/controllers app/models
printf "source 'https://rubygems.org'\ngem 'rails', '~> 8.0'\ngem 'pundit'\n" > Gemfile
cat > app/models/invoice.rb <<'EOF'
class Invoice < ApplicationRecord
  belongs_to :account
end
EOF

git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit --quiet -m "baseline"

cat > app/controllers/invoices_controller.rb <<'EOF'
class InvoicesController < ApplicationController
  def index
    @invoices = Invoice.where(account_id: params[:account_id]).order("created_at desc")
  end
end
EOF
git add .
git commit --quiet -m "add invoices index"

echo "Test 1: Rails project — the review plan includes the Rails stage..."

output=$(run_claude "I just finished the invoices index. Review my changes before I merge. Describe the review stages you will run, then stop — do not dispatch anything." "${CLAUDE_PROMPT_TIMEOUT:-300}")

if ! assert_contains "$output" "rails-reviewer-prompt\|rails convention" "Plans the Rails conventions review stage"; then
    exit 1
fi

if ! assert_contains "$output" "bin/ci" "Plans local CI"; then
    exit 1
fi

echo ""
echo "Test 2: non-Rails project — the Rails stage does not fire..."

PLAIN_PROJECT=$(create_test_project)
trap 'cleanup_test_project "$TEST_PROJECT"; cleanup_test_project "$PLAIN_PROJECT"' EXIT
cd "$PLAIN_PROJECT"

mkdir -p src
printf '{ "name": "widget", "version": "1.0.0" }\n' > package.json
printf 'export const add = (a, b) => a + b;\n' > src/index.js
git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit --quiet -m "baseline"
printf 'export const add = (a, b) => a + b;\nexport const sub = (a, b) => a - b;\n' > src/index.js
git add .
git commit --quiet -m "add sub"

output=$(run_claude "I just finished the sub() helper. Review my changes before I merge. Describe the review stages you will run, then stop — do not dispatch anything." "${CLAUDE_PROMPT_TIMEOUT:-300}")

if ! assert_not_contains "$output" "rails convention" "No Rails stage on a non-Rails project"; then
    exit 1
fi

echo ""
echo "STATUS: PASSED"
