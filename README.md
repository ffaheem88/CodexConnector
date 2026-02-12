# CodexConnector

A bridge between **Claude Code** and **OpenAI Codex CLI** that lets Claude automatically get a second opinion on code changes and implementation plans by sending them to Codex for review.

## Why?

When Claude Code finishes writing code, it can run `codex-review` to have Codex independently check for bugs, edge cases, and improvements. Before starting implementation, it can run `codex-review -a plan` to get Codex's feedback on the approach. Two AI reviewers catch more issues than one.

## Features

- **Two actions** - `review` for code changes, `plan` for reviewing implementation plans and bug fix strategies.
- **Multi-repo support** - Automatically discovers and reviews all git repos in a directory. Point it at a parent folder containing multiple projects and it reviews changes across all of them.
- **Multiple review modes** - Review uncommitted changes, staged changes, branch diffs, or specific commits.
- **Plan input flexibility** - Provide plans as a file (`-f plan.md`), inline text, or both.
- **Custom prompts** - Focus reviews on specific areas (e.g., security, error handling).
- **Automatic skip** - Repos with no changes are skipped automatically (code review only).
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

### Code Review (default)

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

### Plan Review

```bash
# Review a plan file against the codebase
codex-review -a plan -f plan.md

# Review an inline plan description
codex-review -a plan "Add JWT authentication with refresh tokens using middleware"

# Plan file with additional focus instructions
codex-review -a plan -f bugfix-plan.md "Focus on thread safety"

# Review a plan across multiple repos
codex-review -a plan -f migration-plan.md -d ~/projects
```

## Setting Up with Claude Code

To make Claude Code automatically use CodexConnector for code reviews and plan reviews, add a `CLAUDE.md` file to your project root.

### Example CLAUDE.md

Copy this into the `CLAUDE.md` at the root of any project where you want automatic Codex reviews:

```markdown
# CodexConnector Workflow

## Code Review
After completing any code changes, run the Codex review process:
1. Run: `codex-review "Review my changes for bugs and edge cases"`
2. Fix high/medium priority issues identified by Codex
3. Re-run until no significant issues remain

## Plan Review
Before implementing a bug fix or new module, get feedback on your plan:
1. Run: `codex-review -a plan -f plan.md` or `codex-review -a plan "description of approach"`
2. Refine the plan based on Codex feedback
3. Implement once the plan is confirmed solid
4. Run a code review after implementation

## Notes
- Always use read-only mode for reviews (the script handles this)
- If Codex suggests changes you disagree with, explain the reasoning to the user before skipping
```

### Multi-Repo Setup

If you work in a monorepo or a directory with multiple repos side by side, point the review at the parent:

```bash
codex-review -d /path/to/parent-folder
```

The script will automatically find all git repos in immediate subdirectories, check each for changes, and run Codex review on every repo that has modifications.

## How It Works

### Code Review (`-a review`, default)
1. **Discovery** - Scans the target directory and its immediate subdirectories for git repositories
2. **Filter** - Skips repos with no relevant changes (no uncommitted files, commit not found, etc.)
3. **Review** - For each repo with changes, runs `codex review` (or `codex exec` with a custom prompt in read-only sandbox mode)
4. **Report** - Outputs review findings per repo and a final summary

### Plan Review (`-a plan`)
1. **Discovery** - Scans the target directory and its immediate subdirectories for git repositories
2. **Load plan** - Reads the plan file and/or inline prompt
3. **Review** - For each repo, runs `codex exec` in read-only mode with the plan, asking Codex to evaluate feasibility, potential issues, missing considerations, and affected code areas
4. **Report** - Outputs plan review findings per repo and a final summary

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.
