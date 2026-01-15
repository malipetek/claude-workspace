#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  ASYNC AI DELEGATION
#══════════════════════════════════════════════════════════════════════════════
#
#  Runs delegation in background with status tracking.
#  Returns immediately with task_id for status checking.
#
#  USAGE:
#    delegate-async.sh <ai_name> <task_description> <project_path> [options]
#
#  OPTIONS:
#    --branch         Create feature branch for isolation
#    --branch=<name>  Use specific branch name
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"
SETTINGS_FILE="$HOME/.claude-workspace/settings.json"

# Source TLDR library for context extraction
source "$SCRIPT_DIR/lib/tldr.sh" 2>/dev/null || true

#══════════════════════════════════════════════════════════════════════════════
# TLDR Context Enhancement
#══════════════════════════════════════════════════════════════════════════════

get_tldr_context() {
    local task="$1"
    local project="$2"
    local context=""

    # Check if tldr is available and project has indexes
    if ! command -v tldr &>/dev/null; then
        return
    fi

    if [ ! -d "$project/.tldr" ]; then
        return
    fi

    local search_results=""

    # Try semantic search first (if index exists)
    if [ -f "$project/.tldr/cache/semantic/index.faiss" ]; then
        search_results=$(cd "$project" && timeout 10 tldr semantic search "$task" --limit 5 2>/dev/null | head -50)
    fi

    # Fall back to structure/tree if semantic not available
    if [ -z "$search_results" ]; then
        # Get code structure overview
        search_results=$(cd "$project" && timeout 10 tldr structure 2>/dev/null | head -80)
    fi

    if [ -n "$search_results" ]; then
        context="

## Relevant Code Context (from codebase analysis)

\`\`\`
$search_results
\`\`\`
"
    fi

    echo "$context"
}

build_enhanced_prompt() {
    local task="$1"
    local project="$2"
    local project_name=$(basename "$project")

    # Get TLDR context if available
    local tldr_context
    tldr_context=$(get_tldr_context "$task" "$project")

    # Build the enhanced prompt
    local prompt="$task"

    # Add project context
    prompt="$prompt

PROJECT: $project_name
PATH: $project"

    # Add TLDR context if available
    if [ -n "$tldr_context" ]; then
        prompt="$prompt
$tldr_context"
    fi

    # Add instructions for the AI
    prompt="$prompt

INSTRUCTIONS:
- Focus on the task described above
- Make necessary code changes
- Commit your changes with descriptive messages
- Report what you did when complete"

    echo "$prompt"
}

# Parse arguments
AI_NAME=""
TASK_DESC=""
PROJECT_PATH=""
USE_BRANCH=false
BRANCH_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch|-b)
            USE_BRANCH=true
            shift
            ;;
        --branch=*)
            USE_BRANCH=true
            BRANCH_NAME="${1#*=}"
            shift
            ;;
        --no-branch)
            USE_BRANCH=false
            shift
            ;;
        *)
            if [ -z "$AI_NAME" ]; then
                AI_NAME="$1"
            elif [ -z "$TASK_DESC" ]; then
                TASK_DESC="$1"
            elif [ -z "$PROJECT_PATH" ]; then
                PROJECT_PATH="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$AI_NAME" ] || [ -z "$TASK_DESC" ] || [ -z "$PROJECT_PATH" ]; then
    echo "Usage: delegate-async.sh <ai_name> <task_description> <project_path> [--branch]"
    exit 1
fi

# Check settings for default branch behavior
if [ -f "$SETTINGS_FILE" ] && command -v jq &> /dev/null; then
    DEFAULT_BRANCH=$(jq -r '.delegation.use_branches // false' "$SETTINGS_FILE")
    if [ "$DEFAULT_BRANCH" = "true" ] && [ "$USE_BRANCH" = "false" ]; then
        USE_BRANCH=true
    fi
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")
LOG_DIR="$HOME/.claude-workspace/logs/$PROJECT_NAME"
STATUS_DIR="$HOME/.claude-workspace/status"
mkdir -p "$LOG_DIR" "$STATUS_DIR"

# Generate unique task ID
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TASK_ID="${AI_NAME}_${TIMESTAMP}_$$"
STATUS_FILE="$STATUS_DIR/${TASK_ID}.status"
LOG_FILE="$LOG_DIR/${TASK_ID}.log"
OUTPUT_FILE="$LOG_DIR/${TASK_ID}.output"

# Generate branch name if needed
if [ "$USE_BRANCH" = "true" ] && [ -z "$BRANCH_NAME" ]; then
    SAFE_DESC=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
    BRANCH_NAME="delegate/${AI_NAME}/${SAFE_DESC}-${TIMESTAMP}"
fi

# Check auth first (quick check)
AUTH_CHECK=$("$SCRIPT_DIR/check-auth.sh" "$AI_NAME" 2>&1)
AUTH_STATUS=$?

if [ $AUTH_STATUS -eq 2 ]; then
    # CLI not found
    echo "{\"task_id\": \"$TASK_ID\", \"status\": \"failed\", \"error\": \"cli_not_found\", \"message\": \"$AI_NAME CLI not installed\"}"
    exit 1
fi

if [ $AUTH_STATUS -eq 1 ]; then
    # Auth required - fall back to interactive mode
    echo "{\"task_id\": \"$TASK_ID\", \"status\": \"auth_required\", \"fallback\": \"interactive\", \"message\": \"Opening interactive pane for authentication...\"}"

    # Use interactive delegation which opens a Ghostty split pane
    exec "$SCRIPT_DIR/delegate-interactive.sh" "$AI_NAME" "$TASK_DESC" "$PROJECT_PATH"
    exit $?
fi

# Create initial status file
cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "running",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "branch": "$BRANCH_NAME",
  "started": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "output_file": "$OUTPUT_FILE"
}
EOF

# Output task info for Claude to track
echo "{\"task_id\": \"$TASK_ID\", \"status\": \"running\", \"branch\": \"$BRANCH_NAME\", \"status_file\": \"$STATUS_FILE\", \"output_file\": \"$OUTPUT_FILE\"}"

# Run the actual delegation in background
(
    cd "$PROJECT_PATH" || exit 1

    ORIGINAL_BRANCH=""

    # Handle branch creation
    if [ "$USE_BRANCH" = "true" ] && [ -n "$BRANCH_NAME" ]; then
        if git rev-parse --git-dir > /dev/null 2>&1; then
            ORIGINAL_BRANCH=$(git branch --show-current)

            # Stash any uncommitted changes
            git stash push -m "delegate-$TASK_ID" 2>/dev/null

            # Create and checkout new branch
            if ! git checkout -b "$BRANCH_NAME" 2>&1; then
                cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "failed",
  "error": "branch_creation_failed",
  "message": "Failed to create branch: $BRANCH_NAME",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "started": "$(date -Iseconds)",
  "log_file": "$LOG_FILE"
}
EOF
                exit 1
            fi
        fi
    fi

    # Build enhanced prompt with TLDR context
    ENHANCED_PROMPT=$(build_enhanced_prompt "$TASK_DESC" "$PROJECT_PATH")

    # Log header
    {
        echo "=== ASYNC TASK DELEGATION ==="
        echo "Task ID: $TASK_ID"
        echo "AI: $AI_NAME"
        echo "Task: $TASK_DESC"
        echo "Project: $PROJECT_PATH"
        [ -n "$BRANCH_NAME" ] && echo "Branch: $BRANCH_NAME"
        [ -n "$ORIGINAL_BRANCH" ] && echo "Original Branch: $ORIGINAL_BRANCH"
        echo "Started: $(date)"
        echo "=============================="
        echo ""
        echo "Enhanced Prompt:"
        echo "$ENHANCED_PROMPT"
        echo ""
        echo "=============================="
        echo ""
    } > "$LOG_FILE"

    # Execute based on AI (using enhanced prompt with context)
    case $AI_NAME in
        gemini)
            echo "$ENHANCED_PROMPT" | gemini --yolo >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
        zai|opencode)
            echo "$ENHANCED_PROMPT" | opencode >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
        codex)
            echo "$ENHANCED_PROMPT" | codex >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
        aider)
            aider --message "$ENHANCED_PROMPT" >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
        *)
            # Check for custom tool
            if [ -f "$SETTINGS_FILE" ]; then
                CMD=$(jq -r ".ai_tools.$AI_NAME.command // empty" "$SETTINGS_FILE")
                if [ -n "$CMD" ]; then
                    echo "$ENHANCED_PROMPT" | "$CMD" >> "$LOG_FILE" 2>&1
                    EXIT_CODE=$?
                else
                    echo "Unknown AI: $AI_NAME" >> "$LOG_FILE"
                    EXIT_CODE=1
                fi
            else
                echo "Unknown AI: $AI_NAME" >> "$LOG_FILE"
                EXIT_CODE=1
            fi
            ;;
    esac

    # Check output for auth issues
    if grep -qi "login\|authenticate\|sign in\|authorization required\|token expired" "$LOG_FILE"; then
        cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "auth_required",
  "error": "auth_expired_during_execution",
  "message": "$AI_NAME authentication expired during task. Run '$AI_NAME' manually to re-login.",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "branch": "$BRANCH_NAME",
  "original_branch": "$ORIGINAL_BRANCH",
  "started": "$(date -Iseconds)",
  "completed": "$(date -Iseconds)",
  "log_file": "$LOG_FILE"
}
EOF
        exit 1
    fi

    # Determine status
    if [ $EXIT_CODE -eq 0 ]; then
        STATUS="completed"
    else
        STATUS="failed"
    fi

    # Get branch stats if applicable
    COMMITS_MADE=0
    FILES_CHANGED=""
    if [ -n "$BRANCH_NAME" ] && [ -n "$ORIGINAL_BRANCH" ]; then
        COMMITS_MADE=$(git log "$ORIGINAL_BRANCH..$BRANCH_NAME" --oneline 2>/dev/null | wc -l | tr -d ' ')
        FILES_CHANGED=$(git diff --stat "$ORIGINAL_BRANCH" 2>/dev/null | tail -1)
    fi

    # Update status file with completion
    cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "$STATUS",
  "exit_code": $EXIT_CODE,
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "branch": "$BRANCH_NAME",
  "original_branch": "$ORIGINAL_BRANCH",
  "commits_made": $COMMITS_MADE,
  "files_changed": "$FILES_CHANGED",
  "started": "$(date -Iseconds)",
  "completed": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "output_file": "$OUTPUT_FILE"
}
EOF

    # Log completion
    {
        echo ""
        echo "=============================="
        echo "Status: $STATUS"
        echo "Exit Code: $EXIT_CODE"
        [ -n "$BRANCH_NAME" ] && echo "Branch: $BRANCH_NAME (commits: $COMMITS_MADE)"
        echo "Completed: $(date)"
    } >> "$LOG_FILE"

    # Update registry stats
    REGISTRY="$HOME/.claude-workspace/registry.json"
    if command -v jq &> /dev/null && [ -f "$REGISTRY" ]; then
        TEMP_FILE=$(mktemp)
        jq ".stats.total_tasks_delegated += 1 | .stats.${AI_NAME}_tasks += 1 | .metadata.last_updated = \"$(date +%Y-%m-%d)\"" "$REGISTRY" > "$TEMP_FILE" 2>/dev/null
        mv "$TEMP_FILE" "$REGISTRY" 2>/dev/null
    fi

) &

# Disown so it continues after parent exits
disown
