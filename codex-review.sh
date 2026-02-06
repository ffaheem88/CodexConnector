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
MODE="uncommitted"
TARGET_DIR="."
CUSTOM_PROMPT=""
MODEL=""
VERBOSE=false

usage() {
    echo "CodexConnector - Get Codex CLI feedback on code changes"
    echo ""
    echo "Usage: codex-review.sh [OPTIONS] [CUSTOM_PROMPT]"
    echo ""
    echo "Automatically discovers and reviews all git repositories in the target"
    echo "directory. Works with a single repo or multiple repos side by side."
    echo ""
    echo "Options:"
    echo "  -m, --mode MODE      Review mode: uncommitted (default), staged, branch, commit"
    echo "  -b, --base BRANCH    Base branch for comparison (used with --mode branch)"
    echo "  -c, --commit SHA     Commit SHA to review (used with --mode commit)"
    echo "  -d, --dir DIR        Target directory (default: current directory)"
    echo "  --model MODEL        Specify Codex model to use"
    echo "  -v, --verbose        Show verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  codex-review.sh                                    # Review all repos in current dir"
    echo "  codex-review.sh 'Focus on error handling'          # Review with custom instructions"
    echo "  codex-review.sh -d ~/projects                      # Review all repos under ~/projects"
    echo "  codex-review.sh -m branch -b main                  # Review changes vs main branch"
    echo "  codex-review.sh -m commit -c abc123                # Review a specific commit"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Validate mode-specific requirements early
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
echo -e "${GREEN}CodexConnector${NC} - Requesting Codex review"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Mode:${NC} $MODE"
echo -e "${YELLOW}Directory:${NC} $TARGET_DIR"
echo -e "${YELLOW}Repositories:${NC} ${#REPOS[@]} found"
for repo in "${REPOS[@]}"; do
    echo -e "  ${GREEN}•${NC} $(basename "$repo") ${BLUE}(${repo})${NC}"
done

if [[ -n "$CUSTOM_PROMPT" ]]; then
    echo -e "${YELLOW}Instructions:${NC} $CUSTOM_PROMPT"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Track overall exit code
OVERALL_EXIT=0
REPOS_REVIEWED=0
REPOS_SKIPPED=0

# Review each repository
for repo in "${REPOS[@]}"; do
    REPO_NAME="$(basename "$repo")"

    echo -e "\n${BLUE}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}Repository:${NC} ${REPO_NAME} ${BLUE}(${repo})${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"

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
    REPO_EXIT=0
    if [[ -n "$CUSTOM_PROMPT" ]]; then
        EXEC_ARGS=("-s" "read-only")
        if [[ -n "$MODEL" ]]; then
            EXEC_ARGS+=("-m" "$MODEL")
        fi

        REVIEW_PROMPT="Review the uncommitted code changes in this repository (${REPO_NAME}). ${CUSTOM_PROMPT}

Use git diff and git status to see the changes. Provide a detailed code review with findings about bugs, issues, and suggested improvements. Don't make any changes, just report your findings."

        (cd "$repo" && codex exec "${EXEC_ARGS[@]}" "$REVIEW_PROMPT") || REPO_EXIT=$?
    else
        (cd "$repo" && codex review "${CODEX_ARGS[@]}") || REPO_EXIT=$?
    fi

    if [[ $REPO_EXIT -ne 0 ]]; then
        echo -e "\n${RED}Review of ${REPO_NAME} failed with exit code $REPO_EXIT${NC}"
        OVERALL_EXIT=1
    fi
    REPOS_REVIEWED=$((REPOS_REVIEWED + 1))
done

# Final summary
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $OVERALL_EXIT -eq 0 ]]; then
    echo -e "${GREEN}Review complete${NC} - ${REPOS_REVIEWED} repo(s) reviewed, ${REPOS_SKIPPED} skipped (no changes)"
else
    echo -e "${RED}Review finished with errors${NC} - ${REPOS_REVIEWED} repo(s) reviewed, ${REPOS_SKIPPED} skipped"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit $OVERALL_EXIT
