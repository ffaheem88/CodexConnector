# CodexConnector

A bridge between **Claude Code** and **OpenAI Codex CLI** that lets Claude automatically get a second opinion on code changes by sending them to Codex for review.

## Why?

When Claude Code finishes writing code, it can run `codex-review` to have Codex independently check for bugs, edge cases, and improvements. Two AI reviewers catch more issues than one.

## Features

- **Multi-repo support** - Automatically discovers and reviews all git repos in a directory. Point it at a parent folder containing multiple projects and it reviews changes across all of them.
- **Multiple review modes** - Review uncommitted changes, staged changes, branch diffs, or specific commits.
- **Custom prompts** - Focus reviews on specific areas (e.g., security, error handling).
- **Automatic skip** - Repos with no changes are skipped automatically.
- **Cross-platform** - Works on Linux, macOS (Bash), and Windows (PowerShell).

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed and configured
- Git
- Bash (Linux/macOS) or PowerShell 5.1+ (Windows)

## Installation

### Linux / macOS

#### 1. Clone the repo

```bash
git clone https://github.com/ffaheem88/CodexConnector.git
```

#### 2. Make the script executable

```bash
chmod +x CodexConnector/codex-review.sh
```

#### 3. Add to PATH

Add a symlink so `codex-review` is available globally:

```bash
sudo ln -s "$(pwd)/CodexConnector/codex-review.sh" /usr/local/bin/codex-review
```

Or add the directory to your PATH in `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$PATH:/path/to/CodexConnector"
alias codex-review='/path/to/CodexConnector/codex-review.sh'
```

Reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

#### 4. Verify

```bash
codex-review --help
```

### Windows

#### 1. Clone the repo

```powershell
git clone https://github.com/ffaheem88/CodexConnector.git
```

#### 2. Add to PATH

Add the `CodexConnector` folder to your system PATH so the `codex-review.cmd` wrapper is available everywhere:

**Option A - via PowerShell (current user):**

```powershell
$codexPath = (Resolve-Path .\CodexConnector).Path
[Environment]::SetEnvironmentVariable("Path", "$env:Path;$codexPath", "User")
```

**Option B - via System Settings:**

1. Open **Start > Environment Variables**
2. Under **User variables**, edit `Path`
3. Add the full path to the `CodexConnector` folder (e.g., `C:\Users\you\CodexConnector`)

Open a new terminal after updating PATH.

#### 3. Verify

```powershell
codex-review -Help
```

> **Note:** The `codex-review.cmd` wrapper calls the PowerShell script automatically. You can also call the script directly: `powershell -File codex-review.ps1`

## Usage

```bash
# Review uncommitted changes in the current repo
codex-review

# Review with specific instructions
codex-review "Focus on error handling and edge cases"

# Review all repos under a parent directory
codex-review -d ~/projects

# Review changes compared to main branch
codex-review -m branch -b main

# Review a specific commit
codex-review -m commit -c abc123

# Use a specific model
codex-review --model o4-mini "Check for security issues"
```

## Setting Up with Claude Code

To make Claude Code automatically use CodexConnector after every feature or bug fix, add a `CLAUDE.md` file to your project root.

### Example CLAUDE.md

Copy this into the `CLAUDE.md` at the root of any project where you want automatic Codex reviews:

```markdown
# Code Review Workflow

After completing any code changes (features, bug fixes, refactors), you MUST run the Codex review process:

## Process

1. **Run the review** after making changes:
   ```bash
   codex-review "Review the changes I just made for bugs, edge cases, and improvements"
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

## When to Stop

The review loop is complete when:
- No High or Medium priority issues remain
- Codex confirms the code is satisfactory
- Only optional/stylistic suggestions remain (which can be noted but not necessarily fixed)

## Notes

- Always use read-only mode for reviews (the script handles this)
- If Codex suggests changes you disagree with, explain the reasoning to the user before skipping
- For large changes, you may run targeted reviews: `codex-review "Focus only on the authentication changes"`
```

### Multi-Repo Setup

If you work in a monorepo or a directory with multiple repos side by side, point the review at the parent:

```bash
codex-review -d /path/to/parent-folder
```

The script will automatically find all git repos in immediate subdirectories, check each for changes, and run Codex review on every repo that has modifications.

## How It Works

1. **Discovery** - Scans the target directory and its immediate subdirectories for git repositories
2. **Filter** - Skips repos with no relevant changes (no uncommitted files, commit not found, etc.)
3. **Review** - For each repo with changes, runs `codex review` (or `codex exec` with a custom prompt in read-only sandbox mode)
4. **Report** - Outputs review findings per repo and a final summary

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.
