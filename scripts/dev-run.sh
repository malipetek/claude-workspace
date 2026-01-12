#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  DEV PROCESS RUNNER WITH OUTPUT LOGGING
#══════════════════════════════════════════════════════════════════════════════
#
#  DESCRIPTION:
#    Wraps dev commands (npm run dev, cargo watch, tsc --watch, etc.) to:
#    1. Display output normally in your terminal (no obstruction)
#    2. Log output to a file for Claude to read
#    3. Track process info for monitoring
#
#  USAGE:
#    dev-run.sh <name> <command...>
#
#  EXAMPLES:
#    dev-run.sh frontend npm run dev
#    dev-run.sh backend cargo watch -x run
#    dev-run.sh types tsc --watch
#    dev-run.sh api python manage.py runserver
#
#  HOW PROJECT DETECTION WORKS:
#    The script detects which project you're in by:
#    1. Looking for a git root directory
#    2. Using the directory name as the project identifier
#    3. Logs are stored in: ~/.claude-workspace/dev-logs/<project>/<name>.log
#
#    This means if you run:
#      cd ~/code/my-app && dev-run.sh frontend npm run dev
#      cd ~/code/other-app && dev-run.sh frontend npm run dev
#
#    They will have SEPARATE logs:
#      ~/.claude-workspace/dev-logs/my-app/frontend.log
#      ~/.claude-workspace/dev-logs/other-app/frontend.log
#
#  WHY USE THIS:
#    - Claude can check dev-logs.sh instead of running redundant builds
#    - Errors from watch-mode processes are immediately available
#    - Your terminal view is unchanged - output displays normally
#    - Multiple projects stay isolated
#
#══════════════════════════════════════════════════════════════════════════════

NAME=$1
shift
COMMAND="$@"

if [ -z "$NAME" ] || [ -z "$COMMAND" ]; then
    echo "Usage: dev-run.sh <name> <command...>"
    echo ""
    echo "Examples:"
    echo "  dev-run.sh frontend npm run dev"
    echo "  dev-run.sh backend cargo watch -x run"
    echo "  dev-run.sh types tsc --watch"
    echo ""
    echo "Active dev processes:"
    find ~/.claude-workspace/dev-logs -name "*.pid" 2>/dev/null | while read f; do
        PROJECT=$(basename $(dirname "$f"))
        PROC=$(basename "$f" .pid)
        echo "  $PROJECT/$PROC"
    done
    exit 1
fi

# Detect project from git root or current directory
detect_project() {
    # Try to find git root
    local git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ]; then
        basename "$git_root"
    else
        # Fall back to current directory name
        basename "$(pwd)"
    fi
}

PROJECT=$(detect_project)
LOG_DIR="$HOME/.claude-workspace/dev-logs/$PROJECT"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/${NAME}.log"
PID_FILE="$LOG_DIR/${NAME}.pid"
INFO_FILE="$LOG_DIR/${NAME}.info"

# Clean up old log (keep last 1000 lines for context)
if [ -f "$LOG_FILE" ]; then
    tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp"
    mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Write process info
cat > "$INFO_FILE" << EOF
{
  "name": "$NAME",
  "project": "$PROJECT",
  "command": "$COMMAND",
  "started": "$(date -Iseconds)",
  "cwd": "$(pwd)",
  "log_file": "$LOG_FILE"
}
EOF

echo "=== Dev process '$NAME' starting ===" >> "$LOG_FILE"
echo "Project: $PROJECT" >> "$LOG_FILE"
echo "Command: $COMMAND" >> "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "CWD: $(pwd)" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# Also print to terminal
echo "📋 Logging to: $LOG_FILE"
echo ""

# Cleanup function
cleanup() {
    rm -f "$PID_FILE"
    echo "" >> "$LOG_FILE"
    echo "=== Process '$NAME' stopped: $(date) ===" >> "$LOG_FILE"
}
trap cleanup EXIT

# Run with unbuffered output, tee to log file
# Use script for better terminal compatibility (preserves colors in log)
if command -v script &> /dev/null; then
    # macOS/BSD script syntax
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo $$ > "$PID_FILE"
        # Use script to capture with colors, pipe through tee
        script -q /dev/null $COMMAND 2>&1 | tee -a "$LOG_FILE"
    else
        # Linux script syntax
        echo $$ > "$PID_FILE"
        script -q -c "$COMMAND" /dev/null 2>&1 | tee -a "$LOG_FILE"
    fi
else
    # Fallback to unbuffer or stdbuf if available
    echo $$ > "$PID_FILE"
    if command -v unbuffer &> /dev/null; then
        unbuffer $COMMAND 2>&1 | tee -a "$LOG_FILE"
    elif command -v stdbuf &> /dev/null; then
        stdbuf -oL -eL $COMMAND 2>&1 | tee -a "$LOG_FILE"
    else
        $COMMAND 2>&1 | tee -a "$LOG_FILE"
    fi
fi
