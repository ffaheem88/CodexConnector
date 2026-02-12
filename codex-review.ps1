# CodexConnector - Bridge between Claude Code and Codex CLI
# Usage: codex-review.ps1 [OPTIONS] [CUSTOM_PROMPT]

param(
    [Alias("a")]
    [ValidateSet("review", "plan")]
    [string]$Action = "review",

    [Alias("m")]
    [ValidateSet("uncommitted", "staged", "branch", "commit")]
    [string]$Mode = "uncommitted",

    [Alias("b")]
    [string]$Base,

    [Alias("c")]
    [string]$Commit,

    [Alias("f")]
    [string]$File,

    [Alias("d")]
    [string]$Dir = ".",

    [string]$Model,

    [Alias("v")]
    [switch]$Verbose,

    [Alias("h")]
    [switch]$Help,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Remaining
)

# Extract custom prompt from remaining args
$CustomPrompt = if ($Remaining) { $Remaining -join " " } else { "" }

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    param([string]$Text)
    Write-Host ("=" * 60) -ForegroundColor Blue
    Write-Host $Text -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Blue
}

function Write-Separator {
    Write-Host ("-" * 60) -ForegroundColor Blue
}

if ($Help) {
    Write-Host "CodexConnector - Get Codex CLI feedback on code changes and plans"
    Write-Host ""
    Write-Host "Usage: codex-review [OPTIONS] [CUSTOM_PROMPT]"
    Write-Host ""
    Write-Host "Automatically discovers and reviews all git repositories in the target"
    Write-Host "directory. Works with a single repo or multiple repos side by side."
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  review (default)     Review code changes for bugs, edge cases, improvements"
    Write-Host "  plan                 Review a plan (bug fix, new module) against the codebase"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -a, -Action ACTION   Action to perform: review (default), plan"
    Write-Host "  -m, -Mode MODE       Review mode: uncommitted (default), staged, branch, commit"
    Write-Host "  -b, -Base BRANCH     Base branch for comparison (used with -Mode branch)"
    Write-Host "  -c, -Commit SHA      Commit SHA to review (used with -Mode commit)"
    Write-Host "  -f, -File FILE       Plan file to review (used with -Action plan)"
    Write-Host "  -d, -Dir DIR         Target directory (default: current directory)"
    Write-Host "  -Model MODEL         Specify Codex model to use"
    Write-Host "  -v, -Verbose         Show verbose output"
    Write-Host "  -h, -Help            Show this help message"
    Write-Host ""
    Write-Host "Review examples:"
    Write-Host "  codex-review                                        # Review all repos in current dir"
    Write-Host "  codex-review 'Focus on error handling'              # Review with custom instructions"
    Write-Host "  codex-review -d ~\projects                          # Review all repos under ~\projects"
    Write-Host "  codex-review -m branch -b main                      # Review changes vs main branch"
    Write-Host "  codex-review -m commit -c abc123                    # Review a specific commit"
    Write-Host ""
    Write-Host "Plan review examples:"
    Write-Host "  codex-review -a plan -f plan.md                     # Review a plan file"
    Write-Host "  codex-review -a plan 'Add auth using JWT'           # Review an inline plan"
    Write-Host "  codex-review -a plan -f plan.md 'Focus on security' # Plan file + extra instructions"
    exit 0
}

# Resolve target directory to absolute path
$TargetDir = (Resolve-Path -Path $Dir -ErrorAction Stop).Path

# Check if codex is available
if (-not (Get-Command "codex" -ErrorAction SilentlyContinue)) {
    Write-Color "Error: Codex CLI not found. Install it first." "Red"
    exit 1
}

# Warn about flags that don't apply to the chosen action
if ($Action -eq "review" -and $File) {
    Write-Color "Warning: -File is ignored with review action (use -Action plan)" "Yellow"
    $File = ""
}

if ($Action -eq "plan" -and $Mode -ne "uncommitted") {
    Write-Color "Warning: -Mode is ignored with plan action" "Yellow"
}

# Validate plan action requirements
if ($Action -eq "plan") {
    if (-not $File -and -not $CustomPrompt) {
        Write-Color "Error: Plan action requires a plan file (-f) or inline prompt" "Red"
        exit 1
    }
    if ($File) {
        # Resolve plan file to absolute path (relative to CWD, not -Dir)
        $resolvedFile = (Resolve-Path -Path $File -ErrorAction SilentlyContinue).Path
        if (-not $resolvedFile -or -not (Test-Path $resolvedFile)) {
            Write-Color "Error: Plan file not found: $File" "Red"
            exit 1
        }
        $File = $resolvedFile
    }
}

# Validate mode-specific requirements (review action only)
if ($Action -eq "review") {
    switch ($Mode) {
        "branch" {
            if (-not $Base) {
                Write-Color "Error: -Base BRANCH required for branch mode" "Red"
                exit 1
            }
        }
        "commit" {
            if (-not $Commit) {
                Write-Color "Error: -Commit SHA required for commit mode" "Red"
                exit 1
            }
        }
    }
}

# Discover git repositories in the target directory
$Repos = @()

# Check if the target directory itself is a git repo
$gitCheck = git -C $TargetDir rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -eq 0) {
    $repoRoot = (git -C $TargetDir rev-parse --show-toplevel 2>$null).Trim()
    # Normalize path separators for Windows
    $repoRoot = $repoRoot -replace '/', '\'
    $Repos += $repoRoot
}

# Scan immediate subdirectories for additional git repos
$subdirs = Get-ChildItem -Path $TargetDir -Directory -ErrorAction SilentlyContinue
foreach ($subdir in $subdirs) {
    $gitCheck = git -C $subdir.FullName rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $repoRoot = (git -C $subdir.FullName rev-parse --show-toplevel 2>$null).Trim()
        $repoRoot = $repoRoot -replace '/', '\'
        if ($repoRoot -notin $Repos) {
            $Repos += $repoRoot
        }
    }
}

if ($Repos.Count -eq 0) {
    Write-Color "Error: No git repositories found in $TargetDir" "Red"
    exit 1
}

# Show what we're about to do
if ($Action -eq "plan") {
    Write-Header "CodexConnector - Requesting Codex plan review"
} else {
    Write-Header "CodexConnector - Requesting Codex code review"
}
Write-Host "Action:       " -ForegroundColor Yellow -NoNewline; Write-Host $Action
if ($Action -eq "review") {
    Write-Host "Mode:         " -ForegroundColor Yellow -NoNewline; Write-Host $Mode
}
Write-Host "Directory:    " -ForegroundColor Yellow -NoNewline; Write-Host $TargetDir
Write-Host "Repositories: " -ForegroundColor Yellow -NoNewline; Write-Host "$($Repos.Count) found"
foreach ($repo in $Repos) {
    $repoName = Split-Path $repo -Leaf
    Write-Host "  * " -ForegroundColor Green -NoNewline
    Write-Host "$repoName " -NoNewline
    Write-Host "($repo)" -ForegroundColor Blue
}

if ($File) {
    Write-Host "Plan file:    " -ForegroundColor Yellow -NoNewline; Write-Host $File
}
if ($CustomPrompt) {
    Write-Host "Instructions: " -ForegroundColor Yellow -NoNewline; Write-Host $CustomPrompt
}

Write-Host ("=" * 60) -ForegroundColor Blue

# Track overall exit code
$OverallExit = 0
$ReposReviewed = 0
$ReposSkipped = 0

# Load plan file content if provided
$PlanContent = ""
if ($File) {
    $PlanContent = Get-Content -Path $File -Raw
}

# Process each repository
foreach ($repo in $Repos) {
    $repoName = Split-Path $repo -Leaf

    Write-Host ""
    Write-Separator
    Write-Host "Repository: " -ForegroundColor Green -NoNewline
    Write-Host "$repoName " -NoNewline
    Write-Host "($repo)" -ForegroundColor Blue
    Write-Separator

    $repoExit = 0

    if ($Action -eq "plan") {
        # Plan review: send plan to Codex for feedback against this repo's codebase
        $execArgs = @("-s", "read-only")
        if ($Model) {
            $execArgs += "-m", $Model
        }

        $planPrompt = "You are reviewing a plan against the codebase in this repository ($repoName). Analyze the plan for feasibility, potential issues, and suggest improvements.`n`n"

        if ($PlanContent) {
            $planPrompt += "## Plan`n$PlanContent`n`n"
        }

        if ($CustomPrompt) {
            $planPrompt += "## Additional Context`n$CustomPrompt`n`n"
        }

        $planPrompt += "Review this plan in the context of the existing codebase. Provide feedback on:`n"
        $planPrompt += "1. **Feasibility** - Can this be implemented as described given the current code structure?`n"
        $planPrompt += "2. **Potential issues** - What bugs, edge cases, or architectural problems might arise?`n"
        $planPrompt += "3. **Missing considerations** - What has the plan overlooked (error handling, security, performance, etc.)?`n"
        $planPrompt += "4. **Suggested improvements** - How could the approach be refined?`n"
        $planPrompt += "5. **Affected areas** - What existing files/modules will need changes?`n`n"
        $planPrompt += "Explore the codebase to ground your feedback in the actual code. Don't make any changes, just report your findings."

        # Warn if prompt is very large (risk of hitting OS argument length limits)
        $promptLen = $planPrompt.Length
        if ($promptLen -gt 30000) {
            Write-Color "Warning: Plan prompt is very large ($promptLen chars). This may exceed OS command-line limits." "Yellow"
            Write-Color "Consider trimming the plan file or splitting into smaller sections." "Yellow"
        }

        if ($Verbose) {
            Write-Host "Command: " -ForegroundColor Yellow -NoNewline
            Write-Host "codex exec $($execArgs -join ' ') <plan-prompt ($promptLen chars)>"
        }

        Write-Host ""
        Write-Color "Codex Plan Review Output:" "Green"
        Write-Host ""

        Push-Location $repo
        try {
            & codex exec @execArgs $planPrompt
            $repoExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
    }
    else {
        # Code review: existing behavior
        # Check if this repo has changes worth reviewing
        if ($Mode -eq "uncommitted" -or $Mode -eq "staged") {
            $changes = git -C $repo status --short 2>$null
            if (-not $changes) {
                Write-Color "No changes detected, skipping." "Yellow"
                $ReposSkipped++
                continue
            }
            Write-Host ""
            Write-Color "Changes to review:" "Yellow"
            Write-Host $changes
        }
        elseif ($Mode -eq "branch") {
            Write-Host ""
            Write-Color "Changes to review:" "Yellow"
            $logOutput = git -C $repo log --oneline "$Base..HEAD" 2>$null | Select-Object -First 10
            if ($logOutput) { Write-Host $logOutput } else { Write-Host "No commits ahead of $Base" }
        }
        elseif ($Mode -eq "commit") {
            Write-Host ""
            Write-Color "Changes to review:" "Yellow"
            $showOutput = git -C $repo show --stat $Commit --oneline 2>$null | Select-Object -First 15
            if ($LASTEXITCODE -ne 0) {
                Write-Color "Commit $Commit not found in this repo, skipping." "Yellow"
                $ReposSkipped++
                continue
            }
            Write-Host $showOutput
        }

        # Build mode-specific codex args
        $codexArgs = @()
        if ($Model) {
            $codexArgs += "-m", $Model
        }

        switch ($Mode) {
            { $_ -in "uncommitted", "staged" } { $codexArgs += "--uncommitted" }
            "branch" { $codexArgs += "--base", $Base }
            "commit" { $codexArgs += "--commit", $Commit }
        }

        if ($Verbose) {
            Write-Host "Command: " -ForegroundColor Yellow -NoNewline
            Write-Host "codex review $($codexArgs -join ' ') $CustomPrompt"
        }

        Write-Host ""
        Write-Color "Codex Review Output:" "Green"
        Write-Host ""

        # Run codex review from within the repo directory
        Push-Location $repo
        try {
            if ($CustomPrompt) {
                $execArgs = @("-s", "read-only")
                if ($Model) {
                    $execArgs += "-m", $Model
                }

                # Build mode-aware review prompt with appropriate git commands
                $modeDesc = switch ($Mode) {
                    "uncommitted" { "uncommitted" }
                    "staged" { "staged" }
                    "branch" { "on this branch compared to $Base" }
                    "commit" { "in commit $Commit" }
                }

                $gitInstructions = switch ($Mode) {
                    "uncommitted" { "Use ``git diff`` and ``git status`` to see the changes." }
                    "staged" { "Use ``git diff --staged`` to see the staged changes." }
                    "branch" { "Use ``git diff $Base...HEAD`` and ``git log $Base..HEAD`` to see the changes." }
                    "commit" { "Use ``git show $Commit`` to see the changes in this commit." }
                }

                $reviewPrompt = "Review the $modeDesc code changes in this repository ($repoName). $CustomPrompt`n`n$gitInstructions Provide a detailed code review with findings about bugs, issues, and suggested improvements. Don't make any changes, just report your findings."

                $promptLen = $reviewPrompt.Length
                if ($promptLen -gt 30000) {
                    Write-Color "Warning: Review prompt is very large ($promptLen chars). This may exceed OS command-line limits." "Yellow"
                }

                & codex exec @execArgs $reviewPrompt
                $repoExit = $LASTEXITCODE
            }
            else {
                & codex review @codexArgs
                $repoExit = $LASTEXITCODE
            }
        }
        finally {
            Pop-Location
        }
    }

    if ($repoExit -ne 0) {
        Write-Host ""
        $failLabel = if ($Action -eq "plan") { "Plan review" } else { "Review" }
        Write-Color "$failLabel of $repoName failed with exit code $repoExit" "Red"
        $OverallExit = 1
    }
    $ReposReviewed++
}

# Final summary
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Blue
$actionLabel = if ($Action -eq "plan") { "Plan review" } else { "Review" }
if ($OverallExit -eq 0) {
    Write-Color "$actionLabel complete - $ReposReviewed repo(s) reviewed, $ReposSkipped skipped" "Green"
}
else {
    Write-Color "$actionLabel finished with errors - $ReposReviewed repo(s) reviewed, $ReposSkipped skipped" "Red"
}
Write-Host ("=" * 60) -ForegroundColor Blue

exit $OverallExit
