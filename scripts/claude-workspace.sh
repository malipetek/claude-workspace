#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE WRAPPER
#══════════════════════════════════════════════════════════════════════════════
#
#  Runs Claude and cleans up dev processes when Claude exits.
#  Used by the workspace launcher to ensure proper cleanup.
#
#  USAGE:
#    claude-workspace.sh <project_path>
#
#══════════════════════════════════════════════════════════════════════════════

PROJECT_PATH="$1"
SCRIPT_DIR="$HOME/.claude-workspace/scripts"

if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH="$(pwd)"
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")

# Change to project directory
cd "$PROJECT_PATH" || exit 1

# Cleanup function
cleanup() {
    echo ""
    echo "Claude exited. Cleaning up workspace..."
    "$SCRIPT_DIR/workspace-cleanup.sh" "$PROJECT_NAME"

    # Also close the Ghostty window/panes if desired
    # This sends Cmd+W to close the current pane
    # Uncomment if you want auto-close behavior:
    # osascript -e 'tell application "System Events" to keystroke "w" using command down' 2>/dev/null
}

# Set trap to run cleanup on exit
trap cleanup EXIT

# Run Claude
claude "$@"
