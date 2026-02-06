# CodexConnector - Bridge between Claude Code and Codex CLI
# Usage: codex-review.ps1 [OPTIONS] [CUSTOM_PROMPT]

param(
    [Alias("m")]
    [ValidateSet("uncommitted", "staged", "branch", "commit")]
    [string]$Mode = "uncommitted",

    [Alias("b")]
    [string]$Base,

    [Alias("c")]
    [string]$Commit,

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
    Write-Host "CodexConnector - Get Codex CLI feedback on code changes"
    Write-Host ""
    Write-Host "Usage: codex-review [OPTIONS] [CUSTOM_PROMPT]"
    Write-Host ""
    Write-Host "Automatically discovers and reviews all git repositories in the target"
    Write-Host "directory. Works with a single repo or multiple repos side by side."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -m, -Mode MODE       Review mode: uncommitted (default), staged, branch, commit"
    Write-Host "  -b, -Base BRANCH     Base branch for comparison (used with -Mode branch)"
    Write-Host "  -c, -Commit SHA      Commit SHA to review (used with -Mode commit)"
    Write-Host "  -d, -Dir DIR         Target directory (default: current directory)"
    Write-Host "  -Model MODEL         Specify Codex model to use"
    Write-Host "  -v, -Verbose         Show verbose output"
    Write-Host "  -h, -Help            Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  codex-review                                        # Review all repos in current dir"
    Write-Host "  codex-review 'Focus on error handling'              # Review with custom instructions"
    Write-Host "  codex-review -d ~\projects                          # Review all repos under ~\projects"
    Write-Host "  codex-review -m branch -b main                      # Review changes vs main branch"
    Write-Host "  codex-review -m commit -c abc123                    # Review a specific commit"
    exit 0
}

# Resolve target directory to absolute path
$TargetDir = (Resolve-Path -Path $Dir -ErrorAction Stop).Path

# Check if codex is available
if (-not (Get-Command "codex" -ErrorAction SilentlyContinue)) {
    Write-Color "Error: Codex CLI not found. Install it first." "Red"
    exit 1
}

# Validate mode-specific requirements
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
Write-Header "CodexConnector - Requesting Codex review"
Write-Host "Mode:         " -ForegroundColor Yellow -NoNewline; Write-Host $Mode
Write-Host "Directory:    " -ForegroundColor Yellow -NoNewline; Write-Host $TargetDir
Write-Host "Repositories: " -ForegroundColor Yellow -NoNewline; Write-Host "$($Repos.Count) found"
foreach ($repo in $Repos) {
    $repoName = Split-Path $repo -Leaf
    Write-Host "  * " -ForegroundColor Green -NoNewline
    Write-Host "$repoName " -NoNewline
    Write-Host "($repo)" -ForegroundColor Blue
}

if ($CustomPrompt) {
    Write-Host "Instructions: " -ForegroundColor Yellow -NoNewline; Write-Host $CustomPrompt
}

Write-Host ("=" * 60) -ForegroundColor Blue

# Track overall exit code
$OverallExit = 0
$ReposReviewed = 0
$ReposSkipped = 0

# Review each repository
foreach ($repo in $Repos) {
    $repoName = Split-Path $repo -Leaf

    Write-Host ""
    Write-Separator
    Write-Host "Repository: " -ForegroundColor Green -NoNewline
    Write-Host "$repoName " -NoNewline
    Write-Host "($repo)" -ForegroundColor Blue
    Write-Separator

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
    $repoExit = 0
    Push-Location $repo
    try {
        if ($CustomPrompt) {
            $execArgs = @("-s", "read-only")
            if ($Model) {
                $execArgs += "-m", $Model
            }

            $reviewPrompt = "Review the uncommitted code changes in this repository ($repoName). $CustomPrompt`n`nUse git diff and git status to see the changes. Provide a detailed code review with findings about bugs, issues, and suggested improvements. Don't make any changes, just report your findings."

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

    if ($repoExit -ne 0) {
        Write-Host ""
        Write-Color "Review of $repoName failed with exit code $repoExit" "Red"
        $OverallExit = 1
    }
    $ReposReviewed++
}

# Final summary
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Blue
if ($OverallExit -eq 0) {
    Write-Color "Review complete - $ReposReviewed repo(s) reviewed, $ReposSkipped skipped (no changes)" "Green"
}
else {
    Write-Color "Review finished with errors - $ReposReviewed repo(s) reviewed, $ReposSkipped skipped" "Red"
}
Write-Host ("=" * 60) -ForegroundColor Blue

exit $OverallExit
