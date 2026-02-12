#!/bin/bash
# CodexConnector - Bridge between Claude Code and Codex CLI
# Usage: ./codex-review.sh [OPTIONS] [CUSTOM_PROMPT]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTION="review"
MODE="uncommitted"
TARGET_DIR="."
CUSTOM_PROMPT=""
PLAN_FILE=""
MODEL=""
VERBOSE=false

usage() {
    echo "CodexConnector - Get Codex CLI feedback on code changes and plans"
    echo ""
    echo "Usage: codex-review.sh [OPTIONS] [CUSTOM_PROMPT]"
    echo ""
    echo "Automatically discovers and reviews all git repositories in the target"
    echo "directory. Works with a single repo or multiple repos side by side."
    echo ""
    echo "Actions:"
    echo "  review (default)     Review code changes for bugs, edge cases, improvements"
    echo "  plan                 Review a plan (bug fix, new module) against the codebase"
    echo ""
    echo "Options:"
    echo "  -a, --action ACTION  Action to perform: review (default), plan"
    echo "  -m, --mode MODE      Review mode: uncommitted (default), staged, branch, commit"
    echo "  -b, --base BRANCH    Base branch for comparison (used with --mode branch)"
    echo "  -c, --commit SHA     Commit SHA to review (used with --mode commit)"
    echo "  -f, --file FILE      Plan file to review (used with --action plan)"
    echo "  -d, --dir DIR        Target directory (default: current directory)"
    echo "  --model MODEL        Specify Codex model to use"
    echo "  -v, --verbose        Show verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Review examples:"
    echo "  codex-review.sh                                    # Review all repos in current dir"
    echo "  codex-review.sh 'Focus on error handling'          # Review with custom instructions"
    echo "  codex-review.sh -d ~/projects                      # Review all repos under ~/projects"
    echo "  codex-review.sh -m branch -b main                  # Review changes vs main branch"
    echo "  codex-review.sh -m commit -c abc123                # Review a specific commit"
    echo ""
    echo "Plan review examples:"
    echo "  codex-review.sh -a plan -f plan.md                 # Review a plan file"
    echo "  codex-review.sh -a plan 'Add auth using JWT'       # Review an inline plan"
    echo "  codex-review.sh -a plan -f plan.md 'Focus on security'  # Plan file + extra instructions"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -b|--base)
            BASE_BRANCH="$2"
            shift 2
            ;;
        -c|--commit)
            COMMIT_SHA="$2"
            shift 2
            ;;
        -f|--file)
            PLAN_FILE="$2"
            shift 2
            ;;
        -d|--dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
        *)
            CUSTOM_PROMPT="$1"
            shift
            ;;
    esac
done

# Resolve target directory to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# Check if codex is available
if ! command -v codex &> /dev/null; then
    echo -e "${RED}Error: Codex CLI not found. Install it first.${NC}"
    exit 1
fi

# Validate action
case $ACTION in
    review|plan)
        ;;
    *)
        echo -e "${RED}Error: Unknown action '$ACTION'. Use 'review' or 'plan'.${NC}"
        exit 1
        ;;
esac

# Warn about flags that don't apply to the chosen action
if [[ "$ACTION" == "review" && -n "$PLAN_FILE" ]]; then
    echo -e "${YELLOW}Warning: --file is ignored with review action (use -a plan)${NC}"
    PLAN_FILE=""
fi

if [[ "$ACTION" == "plan" && "$MODE" != "uncommitted" ]]; then
    echo -e "${YELLOW}Warning: --mode is ignored with plan action${NC}"
fi

# Validate plan action requirements
if [[ "$ACTION" == "plan" ]]; then
    if [[ -z "$PLAN_FILE" && -z "$CUSTOM_PROMPT" ]]; then
        echo -e "${RED}Error: Plan action requires a plan file (-f) or inline prompt${NC}"
        exit 1
    fi
    if [[ -n "$PLAN_FILE" ]]; then
        # Resolve plan file to absolute path (relative to CWD, not -d)
        if [[ ! -f "$PLAN_FILE" ]]; then
            echo -e "${RED}Error: Plan file not found: $PLAN_FILE${NC}"
            exit 1
        fi
        PLAN_FILE="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"
    fi
fi

# Validate mode-specific requirements (review action only)
if [[ "$ACTION" == "review" ]]; then
    case $MODE in
        uncommitted|staged)
            ;;
        branch)
            if [[ -z "$BASE_BRANCH" ]]; then
                echo -e "${RED}Error: --base BRANCH required for branch mode${NC}"
                exit 1
            fi
            ;;
        commit)
            if [[ -z "$COMMIT_SHA" ]]; then
                echo -e "${RED}Error: --commit SHA required for commit mode${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Error: Unknown mode '$MODE'${NC}"
            exit 1
            ;;
    esac
fi

# Discover git repositories in the target directory
REPOS=()

# Check if the target directory itself is a git repo
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # Get the root of this repo (in case TARGET_DIR is a subdirectory)
    REPO_ROOT="$(git -C "$TARGET_DIR" rev-parse --show-toplevel)"
    REPOS+=("$REPO_ROOT")
fi

# Scan immediate subdirectories for additional git repos
for dir in "$TARGET_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    if git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        REPO_ROOT="$(git -C "$dir" rev-parse --show-toplevel)"
        # Avoid duplicates (e.g., if TARGET_DIR is itself a repo and a subdir resolves to the same root)
        ALREADY_ADDED=false
        for existing in "${REPOS[@]}"; do
            if [[ "$existing" == "$REPO_ROOT" ]]; then
                ALREADY_ADDED=true
                break
            fi
        done
        if [[ "$ALREADY_ADDED" == false ]]; then
            REPOS+=("$REPO_ROOT")
        fi
    fi
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No git repositories found in ${TARGET_DIR}${NC}"
    exit 1
fi

# Show what we're about to do
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$ACTION" == "plan" ]]; then
    echo -e "${GREEN}CodexConnector${NC} - Requesting Codex plan review"
else
    echo -e "${GREEN}CodexConnector${NC} - Requesting Codex code review"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Action:${NC} $ACTION"
if [[ "$ACTION" == "review" ]]; then
    echo -e "${YELLOW}Mode:${NC} $MODE"
fi
echo -e "${YELLOW}Directory:${NC} $TARGET_DIR"
echo -e "${YELLOW}Repositories:${NC} ${#REPOS[@]} found"
for repo in "${REPOS[@]}"; do
    echo -e "  ${GREEN}•${NC} $(basename "$repo") ${BLUE}(${repo})${NC}"
done

if [[ -n "$PLAN_FILE" ]]; then
    echo -e "${YELLOW}Plan file:${NC} $PLAN_FILE"
fi
if [[ -n "$CUSTOM_PROMPT" ]]; then
    echo -e "${YELLOW}Instructions:${NC} $CUSTOM_PROMPT"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Track overall exit code
OVERALL_EXIT=0
REPOS_REVIEWED=0
REPOS_SKIPPED=0

# Load plan file content if provided
PLAN_CONTENT=""
if [[ -n "$PLAN_FILE" ]]; then
    PLAN_CONTENT="$(cat "$PLAN_FILE")"
fi

# Process each repository
for repo in "${REPOS[@]}"; do
    REPO_NAME="$(basename "$repo")"

    echo -e "\n${BLUE}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}Repository:${NC} ${REPO_NAME} ${BLUE}(${repo})${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"

    REPO_EXIT=0

    if [[ "$ACTION" == "plan" ]]; then
        # Plan review: send plan to Codex for feedback against this repo's codebase
        EXEC_ARGS=("-s" "read-only")
        if [[ -n "$MODEL" ]]; then
            EXEC_ARGS+=("-m" "$MODEL")
        fi

        # Build the plan prompt
        PLAN_PROMPT="You are reviewing a plan against the codebase in this repository (${REPO_NAME}). Analyze the plan for feasibility, potential issues, and suggest improvements.

"
        if [[ -n "$PLAN_CONTENT" ]]; then
            PLAN_PROMPT+="## Plan
${PLAN_CONTENT}

"
        fi

        if [[ -n "$CUSTOM_PROMPT" ]]; then
            PLAN_PROMPT+="## Additional Context
${CUSTOM_PROMPT}

"
        fi

        PLAN_PROMPT+="Review this plan in the context of the existing codebase. Provide feedback on:
1. **Feasibility** - Can this be implemented as described given the current code structure?
2. **Potential issues** - What bugs, edge cases, or architectural problems might arise?
3. **Missing considerations** - What has the plan overlooked (error handling, security, performance, etc.)?
4. **Suggested improvements** - How could the approach be refined?
5. **Affected areas** - What existing files/modules will need changes?

Explore the codebase to ground your feedback in the actual code. Don't make any changes, just report your findings."

        # Warn if prompt is very large (risk of hitting OS argument length limits)
        PROMPT_LEN=${#PLAN_PROMPT}
        if [[ $PROMPT_LEN -gt 30000 ]]; then
            echo -e "${YELLOW}Warning: Plan prompt is very large (${PROMPT_LEN} chars). This may exceed OS command-line limits.${NC}"
            echo -e "${YELLOW}Consider trimming the plan file or splitting into smaller sections.${NC}"
        fi

        if [[ "$VERBOSE" == true ]]; then
            echo -e "${YELLOW}Command:${NC} codex exec ${EXEC_ARGS[*]} <plan-prompt (${PROMPT_LEN} chars)>"
        fi

        echo -e "\n${GREEN}Codex Plan Review Output:${NC}\n"

        (cd "$repo" && codex exec "${EXEC_ARGS[@]}" "$PLAN_PROMPT") || REPO_EXIT=$?

    else
        # Code review: existing behavior
        # Check if this repo has changes worth reviewing (for uncommitted/staged modes)
        if [[ "$MODE" == "uncommitted" || "$MODE" == "staged" ]]; then
            CHANGES="$(git -C "$repo" status --short)"
            if [[ -z "$CHANGES" ]]; then
                echo -e "${YELLOW}No changes detected, skipping.${NC}"
                REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
                continue
            fi
            echo -e "\n${YELLOW}Changes to review:${NC}"
            echo "$CHANGES"
        elif [[ "$MODE" == "branch" ]]; then
            echo -e "\n${YELLOW}Changes to review:${NC}"
            git -C "$repo" log --oneline "$BASE_BRANCH"..HEAD 2>/dev/null | head -10 || echo "No commits ahead of $BASE_BRANCH"
        elif [[ "$MODE" == "commit" ]]; then
            echo -e "\n${YELLOW}Changes to review:${NC}"
            git -C "$repo" show --stat "$COMMIT_SHA" --oneline 2>/dev/null | head -15 || {
                echo -e "${YELLOW}Commit ${COMMIT_SHA} not found in this repo, skipping.${NC}"
                REPOS_SKIPPED=$((REPOS_SKIPPED + 1))
                continue
            }
        fi

        # Build mode-specific codex args for this repo
        CODEX_ARGS=()
        if [[ -n "$MODEL" ]]; then
            CODEX_ARGS+=("-m" "$MODEL")
        fi

        case $MODE in
            uncommitted|staged)
                CODEX_ARGS+=("--uncommitted")
                ;;
            branch)
                CODEX_ARGS+=("--base" "$BASE_BRANCH")
                ;;
            commit)
                CODEX_ARGS+=("--commit" "$COMMIT_SHA")
                ;;
        esac

        if [[ "$VERBOSE" == true ]]; then
            echo -e "${YELLOW}Command:${NC} codex review ${CODEX_ARGS[*]} $CUSTOM_PROMPT"
        fi

        echo -e "\n${GREEN}Codex Review Output:${NC}\n"

        # Run codex review from within the repo directory
        if [[ -n "$CUSTOM_PROMPT" ]]; then
            EXEC_ARGS=("-s" "read-only")
            if [[ -n "$MODEL" ]]; then
                EXEC_ARGS+=("-m" "$MODEL")
            fi

            # Build mode-aware review prompt with appropriate git commands
            case $MODE in
                uncommitted)
                    MODE_DESC="uncommitted"
                    GIT_INSTRUCTIONS="Use \`git diff\` and \`git status\` to see the changes."
                    ;;
                staged)
                    MODE_DESC="staged"
                    GIT_INSTRUCTIONS="Use \`git diff --staged\` to see the staged changes."
                    ;;
                branch)
                    MODE_DESC="on this branch compared to ${BASE_BRANCH}"
                    GIT_INSTRUCTIONS="Use \`git diff ${BASE_BRANCH}...HEAD\` and \`git log ${BASE_BRANCH}..HEAD\` to see the changes."
                    ;;
                commit)
                    MODE_DESC="in commit ${COMMIT_SHA}"
                    GIT_INSTRUCTIONS="Use \`git show ${COMMIT_SHA}\` to see the changes in this commit."
                    ;;
            esac

            REVIEW_PROMPT="Review the ${MODE_DESC} code changes in this repository (${REPO_NAME}). ${CUSTOM_PROMPT}

${GIT_INSTRUCTIONS} Provide a detailed code review with findings about bugs, issues, and suggested improvements. Don't make any changes, just report your findings."

            PROMPT_LEN=${#REVIEW_PROMPT}
            if [[ $PROMPT_LEN -gt 30000 ]]; then
                echo -e "${YELLOW}Warning: Review prompt is very large (${PROMPT_LEN} chars). This may exceed OS command-line limits.${NC}"
            fi

            (cd "$repo" && codex exec "${EXEC_ARGS[@]}" "$REVIEW_PROMPT") || REPO_EXIT=$?
        else
            (cd "$repo" && codex review "${CODEX_ARGS[@]}") || REPO_EXIT=$?
        fi
    fi

    if [[ $REPO_EXIT -ne 0 ]]; then
        FAIL_LABEL="Review"
        [[ "$ACTION" == "plan" ]] && FAIL_LABEL="Plan review"
        echo -e "\n${RED}${FAIL_LABEL} of ${REPO_NAME} failed with exit code $REPO_EXIT${NC}"
        OVERALL_EXIT=1
    fi
    REPOS_REVIEWED=$((REPOS_REVIEWED + 1))
done

# Final summary
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ACTION_LABEL="Review"
[[ "$ACTION" == "plan" ]] && ACTION_LABEL="Plan review"
if [[ $OVERALL_EXIT -eq 0 ]]; then
    echo -e "${GREEN}${ACTION_LABEL} complete${NC} - ${REPOS_REVIEWED} repo(s) reviewed, ${REPOS_SKIPPED} skipped"
else
    echo -e "${RED}${ACTION_LABEL} finished with errors${NC} - ${REPOS_REVIEWED} repo(s) reviewed, ${REPOS_SKIPPED} skipped"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit $OVERALL_EXIT
