#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  AI DELEGATION SCRIPT
#══════════════════════════════════════════════════════════════════════════════
#
#  Delegates tasks to external AI tools (Gemini, OpenCode, etc.)
#
#  USAGE:
#    delegate.sh <ai_name> <task_description> <project_path> [options]
#
#  OPTIONS:
#    --visible        Open in split terminal pane (see the AI working)
#    --branch         Create feature branch for isolation
#    --branch=<name>  Use specific branch name
#    --async          Run in background (default for non-visible)
#    --sync           Wait for completion
#
#  EXAMPLES:
#    delegate.sh gemini "Write unit tests for utils.ts" ./my-project
#    delegate.sh gemini "Implement login form" ./my-project --visible --branch
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"
SETTINGS_FILE="$HOME/.claude-workspace/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
AI_NAME=""
TASK_DESC=""
PROJECT_PATH=""
VISIBLE=false
USE_BRANCH=false
BRANCH_NAME=""
ASYNC=true
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --visible|-v)
            VISIBLE=true
            ASYNC=false
            shift
            ;;
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
        --async|-a)
            ASYNC=true
            shift
            ;;
        --sync|-s)
            ASYNC=false
            shift
            ;;
        --output=*)
            OUTPUT_FILE="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "AI Delegation Script"
            echo ""
            echo "Usage: delegate.sh <ai_name> <task_description> <project_path> [options]"
            echo ""
            echo "Options:"
            echo "  --visible, -v     Open in split terminal pane"
            echo "  --branch, -b      Create feature branch for isolation"
            echo "  --branch=<name>   Use specific branch name"
            echo "  --async, -a       Run in background (default)"
            echo "  --sync, -s        Wait for completion"
            echo ""
            echo "Available AI tools:"
            echo "  gemini      Gemini CLI"
            echo "  opencode    OpenCode (Z.ai)"
            echo "  codex       OpenAI Codex"
            echo "  aider       Aider"
            echo "  (custom)    Any tool configured in settings"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
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
    echo "Usage: delegate.sh <ai_name> <task_description> <project_path> [options]"
    echo ""
    echo "Run 'delegate.sh --help' for more options."
    exit 1
fi

# Check settings for defaults
if [ -f "$SETTINGS_FILE" ] && command -v jq &> /dev/null; then
    # Check if visible mode is default
    DEFAULT_VISIBLE=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
    if [ "$DEFAULT_VISIBLE" = "true" ] && [ "$VISIBLE" = "false" ]; then
        VISIBLE=true
        ASYNC=false
    fi

    # Check if branch isolation is default
    DEFAULT_BRANCH=$(jq -r '.delegation.use_branches // false' "$SETTINGS_FILE")
    if [ "$DEFAULT_BRANCH" = "true" ] && [ "$USE_BRANCH" = "false" ]; then
        USE_BRANCH=true
    fi
fi

# Resolve project path
PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: Project directory not found: $PROJECT_PATH${NC}"
    exit 1
fi

# Route to appropriate script
if [ "$VISIBLE" = "true" ]; then
    # Use visible delegation (split pane)
    ARGS=("$AI_NAME" "$TASK_DESC" "$PROJECT_PATH")
    [ "$USE_BRANCH" = "true" ] && ARGS+=("--branch")
    [ -n "$BRANCH_NAME" ] && ARGS+=("--branch=$BRANCH_NAME")

    exec "$SCRIPT_DIR/delegate-visible.sh" "${ARGS[@]}"

elif [ "$ASYNC" = "true" ]; then
    # Use async delegation (background)
    ARGS=("$AI_NAME" "$TASK_DESC" "$PROJECT_PATH")
    [ "$USE_BRANCH" = "true" ] && ARGS+=("--branch")
    [ -n "$BRANCH_NAME" ] && ARGS+=("--branch=$BRANCH_NAME")

    exec "$SCRIPT_DIR/delegate-async.sh" "${ARGS[@]}"

else
    # Synchronous delegation (original behavior)
    PROJECT_NAME=$(basename "$PROJECT_PATH")
    LOG_DIR="$HOME/.claude-workspace/logs/$PROJECT_NAME"
    mkdir -p "$LOG_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    TASK_ID="${AI_NAME}_${TIMESTAMP}"
    LOG_FILE="$LOG_DIR/${TASK_ID}.log"

    # Handle branch creation
    ORIGINAL_BRANCH=""
    if [ "$USE_BRANCH" = "true" ]; then
        cd "$PROJECT_PATH"
        if git rev-parse --git-dir > /dev/null 2>&1; then
            ORIGINAL_BRANCH=$(git branch --show-current)

            if [ -z "$BRANCH_NAME" ]; then
                SAFE_DESC=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-30)
                BRANCH_NAME="delegate/${AI_NAME}/${SAFE_DESC}-${TIMESTAMP}"
            fi

            echo "Creating branch: $BRANCH_NAME"
            git stash push -m "delegate-$TASK_ID" 2>/dev/null
            git checkout -b "$BRANCH_NAME"
        fi
    fi

    # Log task start
    {
        echo "=== TASK DELEGATION ==="
        echo "AI: $AI_NAME"
        echo "Task: $TASK_DESC"
        echo "Project: $PROJECT_PATH"
        [ -n "$BRANCH_NAME" ] && echo "Branch: $BRANCH_NAME"
        echo "Started: $(date)"
        echo "========================"
        echo ""
    } > "$LOG_FILE"

    cd "$PROJECT_PATH" || exit 1

    # Execute based on AI
    case $AI_NAME in
        gemini)
            echo "Delegating to Gemini..." | tee -a "$LOG_FILE"
            if [ -n "$OUTPUT_FILE" ]; then
                echo "$TASK_DESC" | gemini --yolo 2>&1 | tee -a "$LOG_FILE" > "$OUTPUT_FILE"
            else
                echo "$TASK_DESC" | gemini --yolo 2>&1 | tee -a "$LOG_FILE"
            fi
            ;;
        zai|opencode)
            echo "Delegating to OpenCode..." | tee -a "$LOG_FILE"
            if [ -n "$OUTPUT_FILE" ]; then
                echo "$TASK_DESC" | opencode 2>&1 | tee -a "$LOG_FILE" > "$OUTPUT_FILE"
            else
                echo "$TASK_DESC" | opencode 2>&1 | tee -a "$LOG_FILE"
            fi
            ;;
        codex)
            echo "Delegating to Codex..." | tee -a "$LOG_FILE"
            if [ -n "$OUTPUT_FILE" ]; then
                echo "$TASK_DESC" | codex 2>&1 | tee -a "$LOG_FILE" > "$OUTPUT_FILE"
            else
                echo "$TASK_DESC" | codex 2>&1 | tee -a "$LOG_FILE"
            fi
            ;;
        aider)
            echo "Delegating to Aider..." | tee -a "$LOG_FILE"
            aider --message "$TASK_DESC" 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            # Check for custom tool in settings
            if [ -f "$SETTINGS_FILE" ]; then
                CMD=$(jq -r ".ai_tools.$AI_NAME.command // empty" "$SETTINGS_FILE")
                if [ -n "$CMD" ] && command -v "$CMD" &> /dev/null; then
                    echo "Delegating to $AI_NAME ($CMD)..." | tee -a "$LOG_FILE"
                    echo "$TASK_DESC" | "$CMD" 2>&1 | tee -a "$LOG_FILE"
                else
                    echo "Unknown AI: $AI_NAME" | tee -a "$LOG_FILE"
                    exit 1
                fi
            else
                echo "Unknown AI: $AI_NAME" | tee -a "$LOG_FILE"
                exit 1
            fi
            ;;
    esac

    EXIT_CODE=$?

    # Log completion
    {
        echo ""
        echo "========================"
        echo "Exit Code: $EXIT_CODE"
        echo "Completed: $(date)"
        [ -n "$BRANCH_NAME" ] && echo "Branch: $BRANCH_NAME"
    } >> "$LOG_FILE"

    # Show branch summary if applicable
    if [ -n "$BRANCH_NAME" ]; then
        echo ""
        echo "Branch: $BRANCH_NAME"
        echo "To merge: git checkout $ORIGINAL_BRANCH && git merge $BRANCH_NAME"
    fi

    echo ""
    echo -e "${GREEN}✓${NC} Task logged to: $LOG_FILE"
    echo -e "${GREEN}✓${NC} Task ID: $TASK_ID"
fi
