# Claude Code Instructions

## CodexConnector Workflow

CodexConnector has two actions: **review** (review code changes) and **plan** (get feedback on a plan before implementing it).

---

## 1. Code Review Workflow

After completing any code changes (features, bug fixes, refactors), you MUST run the Codex review process before considering the task done.

### Process

1. **Run the review** after making changes:
   ```bash
   codex-review "Review the changes I just made for bugs, edge cases, and improvements"
   ```

   If the project spans multiple repos in the same parent directory, review them all:
   ```bash
   codex-review -d /path/to/parent-folder "Review all changes across repos"
   ```

2. **Analyze the feedback** from Codex and identify:
   - High priority issues (bugs, crashes, security issues)
   - Medium priority issues (edge cases, error handling)
   - Low priority issues (style, naming, best practices)

3. **Fix the issues** starting with high priority, then medium, then low.

4. **Re-run the review** after fixes:
   ```bash
   codex-review "Verify the fixes address the previous issues"
   ```

5. **Repeat steps 2-4** until Codex reports no significant issues remaining.

### When to Stop

The review loop is complete when:
- No High or Medium priority issues remain
- Codex confirms the code is satisfactory
- Only optional/stylistic suggestions remain (which can be noted but not necessarily fixed)

---

## 2. Plan Review Workflow

Before implementing a bug fix or a new module, you SHOULD run the Codex plan review to get feedback on your approach.

### When to Use

- Planning a bug fix and want a second opinion on the approach
- Designing a new module or feature and want architectural feedback
- Evaluating whether an implementation plan accounts for edge cases
- Checking if a proposed change will conflict with existing code

### Process

1. **Write the plan** — either as a file or describe it inline:
   ```bash
   # From a plan file
   codex-review -a plan -f plan.md

   # Inline description
   codex-review -a plan "Fix the race condition in the worker pool by adding a mutex around the shared counter and draining the channel before shutdown"

   # Both: plan file with extra focus instructions
   codex-review -a plan -f plan.md "Focus on thread safety concerns"
   ```

2. **Analyze the feedback** from Codex:
   - Feasibility issues (does the plan work with the current codebase?)
   - Potential bugs or edge cases the plan doesn't address
   - Missing considerations (error handling, security, performance)
   - Suggested improvements to the approach
   - Which existing files/modules will need changes

3. **Refine the plan** based on feedback, then optionally re-run:
   ```bash
   codex-review -a plan -f plan-v2.md "Verify the updated plan addresses previous concerns"
   ```

4. **Proceed to implementation** once Codex confirms the plan is solid.

5. **Run a code review** after implementing:
   ```bash
   codex-review "Review the implementation of the plan"
   ```

### When to Stop

The plan review is complete when:
- Codex confirms the approach is feasible and well-considered
- No major gaps or architectural concerns remain
- You're confident enough to start implementing

---

## Available Modes (Code Review)

```bash
# Default: review uncommitted changes
codex-review "Review my changes"

# Review changes vs a branch
codex-review -m branch -b main "Review all changes since branching from main"

# Review a specific commit
codex-review -m commit -c abc123 "Review this commit"

# Review all repos in a directory
codex-review -d ~/projects "Review changes across all repos"

# Use a specific model
codex-review --model o4-mini "Quick check for bugs"
```

## Example Sessions

### Code Review Session
```
# After writing code
codex-review "Check for bugs and edge cases"

# Codex finds: ZeroDivisionError on empty input
# Fix the issue

codex-review "Verify the empty input fix is correct"

# Codex confirms fix, no more issues
# Done!
```

### Plan Review Session
```
# Before implementing a new auth module
codex-review -a plan -f auth-plan.md

# Codex feedback: plan doesn't handle token refresh, suggests middleware pattern
# Update the plan

codex-review -a plan -f auth-plan-v2.md "Verify token refresh is handled"

# Codex confirms plan is solid
# Now implement it

# After implementation
codex-review "Review the new auth module implementation"
```

## Notes

- Always use read-only mode for reviews (the script handles this)
- **Timeout**: Codex reviews are slow. Set a minimum 10-minute timeout when invoking `codex-review` from a tool or subprocess. For large diffs, multi-repo reviews, or lengthy plan files, increase to 15–20 minutes.
- If Codex suggests changes you disagree with, explain the reasoning to the user before skipping
- For large changes, you may run targeted reviews: `codex-review "Focus only on the authentication changes"`
- The script automatically skips repos with no changes when reviewing multiple repos
- Plan review does NOT skip repos — it always reviews the plan against each repo's codebase
