---
name: requesting-code-review
description: Use when completing tasks, implementing major features, before merging, or when asked to review recent changes - on Rails projects this also runs the Rails conventions review and local CI
---

# Requesting Code Review

Dispatch a code reviewer subagent to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history.

**Core principle:** Review early, review often.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code reviewer subagent:**

Dispatch a `general-purpose` subagent, filling the template at [code-reviewer.md](code-reviewer.md)

**Placeholders:**
- `{DESCRIPTION}` - Brief summary of what you built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit

**3. Rails projects — run the Rails stage too (see below).**

**4. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)

## Rails Projects - MANDATORY

On a Rails project the broad review is not the whole review. Run all three —
the two reviews are read-only and cost one dispatch each, so a partial answer
buys nothing:

1. **Code review** — [code-reviewer.md](code-reviewer.md), as above.
2. **Rails conventions** — dispatch a second `general-purpose` subagent with
   [rails-reviewer-prompt.md](rails-reviewer-prompt.md),
   filling `{FILES_CHANGED}`, `{BASE_SHA}`, `{HEAD_SHA}`. It reads the eight
   `superpowers-rails:rails-*-conventions` skills and checks the diff against
   them.
3. **Local CI** — if `bin/ci` exists, run it. It can run while the reviewers
   work.

Report the three verdicts together — code review, Rails conventions, local CI
— then the findings, most severe first. Your human partner fixes Critical and
Important before merging.

| Rationalization | Reality |
|-----------------|---------|
| "The code reviewer already looked at the Rails code" | Different concern. It reviews correctness and quality; the Rails stage checks THIS project's conventions. |
| "Two reviewers is overkill for a small diff" | Two focused reviews catch more than one broad one. The Rails stage reads a diff, not the codebase. |
| "bin/ci runs in the PR anyway" | Then the reviewers spent their turn on a branch you already know is red. Run it here. |

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from docs/superpowers/plans/deployment-plan.md
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661

[Subagent returns]:
  Strengths: Clean architecture, real tests
  Issues:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Fix progress indicators]
[Continue to Task 3]
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll just review the diff myself instead of dispatching a reviewer" | You're the coordinator — reviewing the diff inline burns the context window you need to keep driving the work. Dispatch a reviewer subagent: the diff and the evaluation live in its context, and only the findings come back to you. |
| "The reviewer needs my whole session history to understand the change" | Hand it precisely crafted context, never your session's history. That keeps the reviewer on the work product, not your thought process. |

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: [code-reviewer.md](code-reviewer.md)
