#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  VISIBLE AI DELEGATION
#══════════════════════════════════════════════════════════════════════════════
#
#  Opens delegation in a Ghostty split pane so user can see the AI working.
#  Optionally creates a feature branch for isolation.
#
#  USAGE:
#    delegate-visible.sh <ai_name> <task_description> <project_path> [options]
#
#  OPTIONS:
#    --branch         Create a feature branch for this task
#    --branch=<name>  Use specific branch name
#    --no-branch      Skip branch creation (default)
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"
SETTINGS_FILE="$HOME/.claude-workspace/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Parse arguments
AI_NAME=""
TASK_DESC=""
PROJECT_PATH=""
USE_BRANCH=false
BRANCH_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
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
    echo "Usage: delegate-visible.sh <ai_name> <task_description> <project_path> [--branch]"
    echo ""
    echo "Options:"
    echo "  --branch         Create a feature branch for isolation"
    echo "  --branch=<name>  Use specific branch name"
    echo "  --no-branch      Skip branch creation (default)"
    exit 1
fi

# Check settings for default branch behavior
if [ -f "$SETTINGS_FILE" ] && command -v jq &> /dev/null; then
    DEFAULT_BRANCH=$(jq -r '.delegation.use_branches // false' "$SETTINGS_FILE")
    if [ "$DEFAULT_BRANCH" = "true" ] && [ "$USE_BRANCH" = "false" ]; then
        # Settings say use branches, but no explicit flag - use setting
        USE_BRANCH=true
    fi
fi

# Resolve project path
PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: Project directory not found: $PROJECT_PATH${NC}"
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")

# Generate task ID
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TASK_ID="${AI_NAME}_${TIMESTAMP}_$$"

# Setup directories
LOG_DIR="$HOME/.claude-workspace/logs/$PROJECT_NAME"
STATUS_DIR="$HOME/.claude-workspace/status"
PID_DIR="$HOME/.claude-workspace/dev-markers"
mkdir -p "$LOG_DIR" "$STATUS_DIR" "$PID_DIR"

LOG_FILE="$LOG_DIR/${TASK_ID}.log"
STATUS_FILE="$STATUS_DIR/${TASK_ID}.status"
PID_FILE="$PID_DIR/delegate_${TASK_ID}.pid"

# Get AI command
get_ai_command() {
    local ai="$1"
    case $ai in
        gemini)
            echo "gemini"
            ;;
        opencode|zai)
            echo "opencode"
            ;;
        codex)
            echo "codex"
            ;;
        aider)
            echo "aider"
            ;;
        *)
            # Check settings for custom tools
            if [ -f "$SETTINGS_FILE" ]; then
                local cmd=$(jq -r ".ai_tools.$ai.command // empty" "$SETTINGS_FILE")
                if [ -n "$cmd" ]; then
                    echo "$cmd"
                    return
                fi
            fi
            echo "$ai"
            ;;
    esac
}

AI_CMD=$(get_ai_command "$AI_NAME")

# Check if AI is installed
if ! command -v "$AI_CMD" &> /dev/null; then
    echo -e "${RED}Error: $AI_NAME CLI not found (command: $AI_CMD)${NC}"
    exit 1
fi

# Generate branch name if needed
if [ "$USE_BRANCH" = true ] && [ -z "$BRANCH_NAME" ]; then
    # Create branch name from task description (sanitized)
    SAFE_DESC=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
    BRANCH_NAME="delegate/${AI_NAME}/${SAFE_DESC}-${TIMESTAMP}"
fi

# Create the delegation runner script
RUNNER_SCRIPT=$(mktemp)
chmod +x "$RUNNER_SCRIPT"

cat > "$RUNNER_SCRIPT" << 'SCRIPT_HEADER'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_HEADER

cat >> "$RUNNER_SCRIPT" << SCRIPT_VARS
AI_NAME="$AI_NAME"
AI_CMD="$AI_CMD"
TASK_DESC="$TASK_DESC"
PROJECT_PATH="$PROJECT_PATH"
PROJECT_NAME="$PROJECT_NAME"
TASK_ID="$TASK_ID"
LOG_FILE="$LOG_FILE"
STATUS_FILE="$STATUS_FILE"
PID_FILE="$PID_FILE"
USE_BRANCH="$USE_BRANCH"
BRANCH_NAME="$BRANCH_NAME"
SCRIPT_VARS

cat >> "$RUNNER_SCRIPT" << 'SCRIPT_BODY'

# Save PID
echo $$ > "$PID_FILE"

# Cleanup on exit
cleanup() {
    rm -f "$PID_FILE"
}
trap cleanup EXIT

# Header
clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}DELEGATED TASK${NC} - $AI_NAME"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Task:${NC} $TASK_DESC"
echo -e "${BLUE}Project:${NC} $PROJECT_PATH"
echo -e "${BLUE}Task ID:${NC} $TASK_ID"
echo ""

cd "$PROJECT_PATH" || exit 1

# Handle branch creation
ORIGINAL_BRANCH=""
if [ "$USE_BRANCH" = "true" ]; then
    # Check if git repo
    if git rev-parse --git-dir > /dev/null 2>&1; then
        ORIGINAL_BRANCH=$(git branch --show-current)

        echo -e "${BLUE}Branch Isolation:${NC}"
        echo -e "  Original: $ORIGINAL_BRANCH"
        echo -e "  Creating: $BRANCH_NAME"
        echo ""

        # Stash any uncommitted changes
        STASH_RESULT=$(git stash push -m "delegate-$TASK_ID" 2>&1)
        STASHED=false
        if [[ "$STASH_RESULT" != *"No local changes"* ]]; then
            STASHED=true
            echo -e "${DIM}Stashed uncommitted changes${NC}"
        fi

        # Create and checkout new branch
        git checkout -b "$BRANCH_NAME" 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to create branch${NC}"
            # Restore stash if we stashed
            if [ "$STASHED" = true ]; then
                git stash pop
            fi
            exit 1
        fi

        echo -e "${GREEN}✓${NC} Working on branch: $BRANCH_NAME"
        echo ""
    else
        echo -e "${YELLOW}Warning: Not a git repository, skipping branch isolation${NC}"
        echo ""
        USE_BRANCH=false
    fi
fi

# Create status file
cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "running",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "branch": "$BRANCH_NAME",
  "original_branch": "$ORIGINAL_BRANCH",
  "started": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "visible": true
}
EOF

# Start logging
{
    echo "=== VISIBLE DELEGATION ==="
    echo "Task ID: $TASK_ID"
    echo "AI: $AI_NAME"
    echo "Task: $TASK_DESC"
    echo "Project: $PROJECT_PATH"
    [ -n "$BRANCH_NAME" ] && echo "Branch: $BRANCH_NAME"
    echo "Started: $(date)"
    echo "=========================="
    echo ""
} > "$LOG_FILE"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Starting $AI_NAME...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Run the AI with the task
# We use script to capture output while showing it
case $AI_NAME in
    gemini)
        echo "$TASK_DESC" | "$AI_CMD" --yolo 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[1]}
        ;;
    opencode|zai)
        echo "$TASK_DESC" | "$AI_CMD" 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[1]}
        ;;
    aider)
        "$AI_CMD" --message "$TASK_DESC" 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
        ;;
    *)
        # Generic: pipe task to command
        echo "$TASK_DESC" | "$AI_CMD" 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[1]}
        ;;
esac

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Determine status
if [ $EXIT_CODE -eq 0 ]; then
    STATUS="completed"
    echo -e "${GREEN}✓ Task completed successfully${NC}"
else
    STATUS="failed"
    echo -e "${RED}✗ Task failed (exit code: $EXIT_CODE)${NC}"
fi

# Show branch info if applicable
if [ "$USE_BRANCH" = "true" ] && [ -n "$BRANCH_NAME" ]; then
    echo ""
    echo -e "${BLUE}Branch Summary:${NC}"

    # Show commits made on this branch
    COMMITS=$(git log "$ORIGINAL_BRANCH..$BRANCH_NAME" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COMMITS" -gt 0 ]; then
        echo -e "  ${GREEN}$COMMITS commit(s)${NC} on $BRANCH_NAME"
        git log "$ORIGINAL_BRANCH..$BRANCH_NAME" --oneline 2>/dev/null | head -5 | while read line; do
            echo -e "    ${DIM}$line${NC}"
        done
    else
        echo -e "  ${YELLOW}No commits made${NC}"
    fi

    # Show file changes
    CHANGES=$(git diff --stat "$ORIGINAL_BRANCH" 2>/dev/null | tail -1)
    if [ -n "$CHANGES" ]; then
        echo -e "  $CHANGES"
    fi

    echo ""
    echo -e "${YELLOW}Branch remains checked out: $BRANCH_NAME${NC}"
    echo -e "${DIM}To merge: git checkout $ORIGINAL_BRANCH && git merge $BRANCH_NAME${NC}"
    echo -e "${DIM}To discard: git checkout $ORIGINAL_BRANCH && git branch -D $BRANCH_NAME${NC}"
fi

# Update status file
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
  "started": "$(date -Iseconds)",
  "completed": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "visible": true
}
EOF

# Log completion
{
    echo ""
    echo "=========================="
    echo "Status: $STATUS"
    echo "Exit Code: $EXIT_CODE"
    echo "Completed: $(date)"
} >> "$LOG_FILE"

echo ""
echo -e "${DIM}Log: $LOG_FILE${NC}"
echo -e "${DIM}Press any key to close...${NC}"
read -n 1

SCRIPT_BODY

# Now open Ghostty split with the runner script
echo -e "${BLUE}Opening delegation in split pane...${NC}"

# Create AppleScript to open a new split
APPLESCRIPT=$(mktemp)
cat > "$APPLESCRIPT" << EOF
tell application "Ghostty"
    activate
    delay 0.3
    tell application "System Events"
        keystroke "d" using {shift down, command down}
        delay 0.5
        keystroke "$RUNNER_SCRIPT"
        delay 0.1
        key code 36
    end tell
end tell
EOF

# Try to run AppleScript
if osascript "$APPLESCRIPT" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Delegation started in split pane"
    echo -e "${DIM}Task ID: $TASK_ID${NC}"
    if [ "$USE_BRANCH" = true ]; then
        echo -e "${DIM}Branch: $BRANCH_NAME${NC}"
    fi
else
    echo -e "${YELLOW}Could not open split pane (Accessibility permissions needed)${NC}"
    echo -e "Running in current terminal instead..."
    echo ""
    bash "$RUNNER_SCRIPT"
fi

rm -f "$APPLESCRIPT"

# Output task info for tracking
echo ""
echo "{\"task_id\": \"$TASK_ID\", \"branch\": \"$BRANCH_NAME\", \"status_file\": \"$STATUS_FILE\", \"visible\": true}"
