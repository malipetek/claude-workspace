#!/bin/bash

# Async AI Delegation Script
# Usage: ./delegate-async.sh <ai_name> <task_description> <project_path>
# Runs delegation in background and writes status to a tracking file
# Returns immediately with task_id for status checking

AI_NAME=$1
TASK_DESC=$2
PROJECT_PATH=$3

if [ -z "$AI_NAME" ] || [ -z "$TASK_DESC" ] || [ -z "$PROJECT_PATH" ]; then
    echo "Usage: ./delegate-async.sh <ai_name> <task_description> <project_path>"
    echo "ai_name: gemini, zai"
    exit 1
fi

SCRIPT_DIR="$HOME/.claude-workspace/scripts"
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

# Check auth first (quick check)
AUTH_CHECK=$("$SCRIPT_DIR/check-auth.sh" "$AI_NAME" 2>&1)
AUTH_STATUS=$?

if [ $AUTH_STATUS -eq 2 ]; then
    # CLI not found
    echo "{\"task_id\": \"$TASK_ID\", \"status\": \"failed\", \"error\": \"cli_not_found\", \"message\": \"$AI_NAME CLI not installed\"}"
    exit 1
fi

if [ $AUTH_STATUS -eq 1 ]; then
    # Auth required
    cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "auth_required",
  "error": "auth_required",
  "message": "$AI_NAME CLI requires authentication. Run '$AI_NAME' manually in terminal to login.",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "started": "$(date -Iseconds)",
  "log_file": "$LOG_FILE"
}
EOF
    cat "$STATUS_FILE"
    exit 1
fi

# Create initial status file
cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "running",
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
  "started": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "output_file": "$OUTPUT_FILE"
}
EOF

# Output task info for Claude to track
echo "{\"task_id\": \"$TASK_ID\", \"status\": \"running\", \"status_file\": \"$STATUS_FILE\", \"output_file\": \"$OUTPUT_FILE\"}"

# Run the actual delegation in background
(
    cd "$PROJECT_PATH" || exit 1

    # Log header
    {
        echo "=== ASYNC TASK DELEGATION ==="
        echo "Task ID: $TASK_ID"
        echo "AI: $AI_NAME"
        echo "Task: $TASK_DESC"
        echo "Project: $PROJECT_PATH"
        echo "Started: $(date)"
        echo "=============================="
        echo ""
    } > "$LOG_FILE"

    # Execute based on AI
    case $AI_NAME in
        gemini)
            echo "$TASK_DESC" | gemini --yolo >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
        zai)
            echo "$TASK_DESC" | opencode >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            ;;
    esac

    # Check output for auth issues that might have occurred mid-execution
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
  "started": "$(date -Iseconds)",
  "completed": "$(date -Iseconds)",
  "log_file": "$LOG_FILE"
}
EOF
        exit 1
    fi

    # Update status file with completion
    if [ $EXIT_CODE -eq 0 ]; then
        STATUS="completed"
    else
        STATUS="failed"
    fi

    cat > "$STATUS_FILE" << EOF
{
  "task_id": "$TASK_ID",
  "ai": "$AI_NAME",
  "status": "$STATUS",
  "exit_code": $EXIT_CODE,
  "task": "$TASK_DESC",
  "project": "$PROJECT_PATH",
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
