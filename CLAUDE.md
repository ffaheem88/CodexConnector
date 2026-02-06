# Claude Code Instructions

## Code Review Workflow

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

### Available Modes

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

### Example Session

```
# After writing code
codex-review "Check for bugs and edge cases"

# Codex finds: ZeroDivisionError on empty input
# Fix the issue

codex-review "Verify the empty input fix is correct"

# Codex confirms fix, no more issues
# Done!
```

## Notes

- Always use read-only mode for reviews (the script handles this)
- If Codex suggests changes you disagree with, explain the reasoning to the user before skipping
- For large changes, you may run targeted reviews: `codex-review "Focus only on the authentication changes"`
- The script automatically skips repos with no changes when reviewing multiple repos
