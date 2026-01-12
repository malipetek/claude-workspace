#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  WORKSPACE CLEANUP
#══════════════════════════════════════════════════════════════════════════════
#
#  Kills all dev processes for a project.
#  Called automatically when Claude exits from a workspace session.
#
#  USAGE:
#    workspace-cleanup.sh <project_name>
#
#══════════════════════════════════════════════════════════════════════════════

PROJECT_NAME="$1"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: workspace-cleanup.sh <project_name>"
    exit 1
fi

LOG_DIR="$HOME/.claude-workspace/dev-logs/$PROJECT_NAME"

if [ ! -d "$LOG_DIR" ]; then
    exit 0
fi

echo ""
echo "Cleaning up dev processes for: $PROJECT_NAME"

# Find and kill all processes with PID files
for pid_file in "$LOG_DIR"/*.pid; do
    [ -f "$pid_file" ] || continue

    PROC_NAME=$(basename "$pid_file" .pid)
    PID=$(cat "$pid_file" 2>/dev/null)

    if [ -n "$PID" ]; then
        # Check if process is still running
        if kill -0 "$PID" 2>/dev/null; then
            echo "  Stopping $PROC_NAME (PID: $PID)..."

            # Try graceful shutdown first (SIGTERM)
            kill "$PID" 2>/dev/null

            # Wait a moment
            sleep 0.5

            # Force kill if still running (SIGKILL)
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null
            fi

            echo "  ✓ $PROC_NAME stopped"
        else
            echo "  $PROC_NAME already stopped"
        fi

        # Clean up PID file
        rm -f "$pid_file"
    fi
done

echo "✓ Cleanup complete"
