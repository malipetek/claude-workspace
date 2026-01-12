#!/bin/bash

# AI Delegation Script
# Usage: ./delegate.sh <ai_name> <task_description> <project_path> [output_file]

AI_NAME=$1
TASK_DESC=$2
PROJECT_PATH=$3
OUTPUT_FILE=$4

if [ -z "$AI_NAME" ] || [ -z "$TASK_DESC" ] || [ -z "$PROJECT_PATH" ]; then
    echo "Usage: ./delegate.sh <ai_name> <task_description> <project_path> [output_file]"
    echo "ai_name: gemini, zai, claude"
    exit 1
fi

# Create log directory for this project
PROJECT_NAME=$(basename "$PROJECT_PATH")
LOG_DIR="$HOME/.claude-workspace/logs/$PROJECT_NAME"
mkdir -p "$LOG_DIR"

# Generate timestamp and task ID
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TASK_ID="${AI_NAME}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${TASK_ID}.log"

# Log task start
echo "=== TASK DELEGATION ===" > "$LOG_FILE"
echo "AI: $AI_NAME" >> "$LOG_FILE"
echo "Task: $TASK_DESC" >> "$LOG_FILE"
echo "Project: $PROJECT_PATH" >> "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Change to project directory
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
    zai)
        echo "Delegating to Z.ai (opencode)..." | tee -a "$LOG_FILE"
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$TASK_DESC" | opencode 2>&1 | tee -a "$LOG_FILE" > "$OUTPUT_FILE"
        else
            echo "$TASK_DESC" | opencode 2>&1 | tee -a "$LOG_FILE"
        fi
        ;;
    claude)
        echo "Executing with Claude..." | tee -a "$LOG_FILE"
        echo "Note: Claude should be executed directly, not via this script" | tee -a "$LOG_FILE"
        ;;
    *)
        echo "Unknown AI: $AI_NAME" | tee -a "$LOG_FILE"
        echo "Supported: gemini, zai, claude" | tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# Log completion
echo "" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"
echo "Completed: $(date)" >> "$LOG_FILE"
echo "Log: $LOG_FILE" >> "$LOG_FILE"

# Update registry stats (simple counter increment)
REGISTRY="$HOME/.claude-workspace/registry.json"
if command -v jq &> /dev/null; then
    # Use jq to update stats if available
    TEMP_FILE=$(mktemp)
    jq ".stats.total_tasks_delegated += 1 | .stats.${AI_NAME}_tasks += 1 | .metadata.last_updated = \"$(date +%Y-%m-%d)\"" "$REGISTRY" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$REGISTRY"
fi

echo ""
echo "✓ Task logged to: $LOG_FILE"
echo "✓ Task ID: $TASK_ID"
