#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE WRAPPER
#══════════════════════════════════════════════════════════════════════════════
#
#  Runs the configured AI coding tool and cleans up dev processes when it exits.
#  Used by the workspace launcher to ensure proper cleanup.
#
#  USAGE:
#    claude-workspace.sh <project_path>
#
#══════════════════════════════════════════════════════════════════════════════

PROJECT_PATH="$1"
SCRIPT_DIR="$HOME/.claude-workspace/scripts"
SETTINGS_FILE="$HOME/.claude-workspace/settings.json"

if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH="$(pwd)"
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")

# Change to project directory
cd "$PROJECT_PATH" || exit 1

# Get main coding tool from settings
MAIN_TOOL="claude"
if [ -f "$SETTINGS_FILE" ] && command -v jq &> /dev/null; then
    MAIN_TOOL=$(jq -r '.main_coding_tool // "claude"' "$SETTINGS_FILE")
fi

TOOL_CMD=""
TOOL_NAME=""

# Get the command for the selected tool
case "$MAIN_TOOL" in
    claude)
        TOOL_CMD="claude --dangerously-skip-permissions"
        TOOL_NAME="Claude"
        ;;
    gemini)
        TOOL_CMD="gemini --yolo"
        TOOL_NAME="Gemini"
        ;;
    opencode)
        TOOL_CMD="opencode"
        TOOL_NAME="OpenCode"
        ;;
    codex)
        TOOL_CMD="codex"
        TOOL_NAME="Codex"
        ;;
    aider)
        TOOL_CMD="aider"
        TOOL_NAME="Aider"
        ;;
    continue)
        TOOL_CMD="continue"
        TOOL_NAME="Continue"
        ;;
    *)
        # Try custom tool from settings
        if [ -f "$SETTINGS_FILE" ]; then
            TOOL_CMD=$(jq -r ".ai_tools.$MAIN_TOOL.command // \"\"" "$SETTINGS_FILE")
            TOOL_NAME=$(jq -r ".ai_tools.$MAIN_TOOL.name // \"$MAIN_TOOL\"" "$SETTINGS_FILE")
        fi

        # Fallback to claude if unknown or not found
        if [ -z "$TOOL_CMD" ]; then
            TOOL_CMD="claude --dangerously-skip-permissions"
            TOOL_NAME="Claude"
        fi
        ;;
esac

# Cleanup function
cleanup() {
    echo ""
    echo "$TOOL_NAME exited. Cleaning up workspace..."
    "$SCRIPT_DIR/workspace-cleanup.sh" "$PROJECT_NAME"

    # Also close the Ghostty window/panes if desired
    # This sends Cmd+W to close the current pane
    # Uncomment if you want auto-close behavior:
    # osascript -e 'tell application "System Events" to keystroke "w" using command down' 2>/dev/null
}

# Set trap to run cleanup on exit
trap cleanup EXIT

# Run the selected AI coding tool
eval "$TOOL_CMD"
