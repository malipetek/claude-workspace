#!/bin/bash

# Parallel AI Delegation Script
# Usage: ./parallel-delegate.sh <project_path>
# Reads tasks from tasks.json and executes them in parallel

PROJECT_PATH=$1

if [ -z "$PROJECT_PATH" ]; then
    echo "Usage: ./parallel-delegate.sh <project_path>"
    exit 1
fi

TASKS_FILE="$HOME/.claude-workspace/tasks.json"

if [ ! -f "$TASKS_FILE" ]; then
    echo "Error: tasks.json not found at $TASKS_FILE"
    echo "Create it with structure: {\"tasks\": [{\"ai\": \"gemini\", \"description\": \"...\"}]}"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for parallel delegation"
    echo "Install with: brew install jq"
    exit 1
fi

# Read tasks and execute in parallel
SCRIPT_DIR="$HOME/.claude-workspace/scripts"
PIDS=()

echo "Starting parallel delegation..."
echo ""

# Get number of tasks
TASK_COUNT=$(jq '.tasks | length' "$TASKS_FILE")

for i in $(seq 0 $(($TASK_COUNT - 1))); do
    AI=$(jq -r ".tasks[$i].ai" "$TASKS_FILE")
    TASK=$(jq -r ".tasks[$i].description" "$TASKS_FILE")

    echo "[$i] Launching $AI: $TASK"

    # Run in background
    "$SCRIPT_DIR/delegate.sh" "$AI" "$TASK" "$PROJECT_PATH" &
    PIDS+=($!)
done

echo ""
echo "Waiting for ${#PIDS[@]} tasks to complete..."
echo ""

# Wait for all background processes
for pid in ${PIDS[@]}; do
    wait $pid
done

echo ""
echo "✓ All tasks completed!"

# Clear tasks file
echo '{"tasks": []}' > "$TASKS_FILE"
