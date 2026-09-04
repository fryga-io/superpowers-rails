---
description: "Run full code review: task review (spec compliance + code quality), plus Rails conventions (if Rails)"
---

# Full Code Review

Run the full review pipeline on recent changes.

## Step 1: Gather Context

Determine what to review:
- If user specified files/commits: use those
- Otherwise: review changes since last review or last commit

Get git SHAs:
```bash
git log --oneline -5  # Find BASE_SHA and HEAD_SHA
git diff --name-only BASE_SHA HEAD_SHA  # Files changed
```

## Step 2: Task Review (spec compliance + code quality)

Write the review package to one file, then dispatch the task reviewer using
the template at `skills/subagent-driven-development/task-reviewer-prompt.md`.
`/codereview` runs outside the SDD loop, so there is no plan file and no plan
workspace — build the file with git directly rather than
`scripts/review-package`, which requires a plan:

```bash
out=$(mktemp -t review-package)
{ echo "# Review package: BASE_SHA..HEAD_SHA"; echo
  echo "## Commits";      git log --oneline BASE_SHA..HEAD_SHA; echo
  echo "## Files changed"; git diff --stat BASE_SHA..HEAD_SHA; echo
  echo "## Diff";          git diff -U10 BASE_SHA..HEAD_SHA
} > "$out"; echo "$out"
```

Pass the printed path to the reviewer — it reads the commit list, stat summary,
and full diff in one call, and the diff never enters your context:

```
Task tool (general-purpose):
  description: "Task review (spec + quality)"
  prompt: [Use template, fill in requirements and the review-package path]
```

**If issues found:** Report and stop. User must fix before continuing.

## Step 3: Rails Conventions Review (Rails projects only)

Check if Rails project (look for Gemfile with rails, app/controllers, etc.)

If Rails, dispatch rails reviewer using the template at `skills/subagent-driven-development/rails-reviewer-prompt.md`:

```
Task tool (general-purpose):
  Use template at skills/subagent-driven-development/rails-reviewer-prompt.md
  FILES_CHANGED: [list]
  BASE_SHA: [sha]
  HEAD_SHA: [sha]
```

**If violations found:** Report and stop. User must fix before continuing.

## Step 4: Run Local CI (if available)

If `bin/ci` exists, run it. Can run in parallel with review agents. If it fails, stop and report.

## Step 5: Report

Summarize all review results:
- ✅ Spec compliance: [passed/issues]
- ✅ Code quality: [passed/issues]
- ✅ Rails conventions: [passed/skipped/issues]
- ✅ Local CI: [passed/skipped/failed]

If all passed: "Ready for merge/PR"
If any failed: List issues with file:line references
