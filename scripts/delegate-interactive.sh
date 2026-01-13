#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  INTERACTIVE AI DELEGATION
#══════════════════════════════════════════════════════════════════════════════
#
#  Opens a new Ghostty split pane for AI delegation.
#  Useful when AI CLI requires authentication or for visible execution.
#
#  USAGE:
#    delegate-interactive.sh <ai_name> <task_description> <project_path>
#
#  The script will:
#    1. Open a new Ghostty split pane to the right
#    2. CD to the project directory
#    3. Type the AI command with the prompt (but NOT execute)
#    4. User can authenticate if needed, then press Enter to run
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"
source "$SCRIPT_DIR/lib/tldr.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

# Parse arguments
AI_NAME="$1"
TASK_DESC="$2"
PROJECT_PATH="$3"

if [ -z "$AI_NAME" ] || [ -z "$TASK_DESC" ] || [ -z "$PROJECT_PATH" ]; then
    echo "Usage: delegate-interactive.sh <ai_name> <task_description> <project_path>"
    exit 1
fi

# Resolve project path
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd)
PROJECT_NAME=$(basename "$PROJECT_PATH")

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

    # Try to get semantic search results for the task
    local search_results
    search_results=$(cd "$project" && tldr semantic "$task" --limit 5 2>/dev/null | head -50)

    if [ -n "$search_results" ]; then
        context="

## Relevant Code Context (from TLDR semantic search)

\`\`\`
$search_results
\`\`\`
"
    fi

    echo "$context"
}

#══════════════════════════════════════════════════════════════════════════════
# Build the prompt with context
#══════════════════════════════════════════════════════════════════════════════

build_enhanced_prompt() {
    local task="$1"
    local project="$2"

    # Get TLDR context if available
    local tldr_context
    tldr_context=$(get_tldr_context "$task" "$project")

    # Build the enhanced prompt
    local prompt="$task"

    # Add project context
    prompt="$prompt

PROJECT: $PROJECT_NAME
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

#══════════════════════════════════════════════════════════════════════════════
# Build AI command
#══════════════════════════════════════════════════════════════════════════════

get_ai_command() {
    local ai="$1"
    local prompt="$2"

    # Escape special characters for shell
    local escaped_prompt
    escaped_prompt=$(printf '%s' "$prompt" | sed "s/'/'\\\\''/g")

    case $ai in
        gemini)
            echo "gemini --yolo"
            ;;
        opencode|zai)
            echo "opencode"
            ;;
        codex)
            echo "codex"
            ;;
        aider)
            echo "aider --message '$escaped_prompt'"
            ;;
        claude)
            echo "claude --dangerously-skip-permissions"
            ;;
        *)
            echo "$ai"
            ;;
    esac
}

#══════════════════════════════════════════════════════════════════════════════
# Open Ghostty split and type command
#══════════════════════════════════════════════════════════════════════════════

open_ghostty_delegate() {
    local ai="$1"
    local prompt="$2"
    local project="$3"

    # Get the AI command
    local ai_cmd
    ai_cmd=$(get_ai_command "$ai" "$prompt")

    # For non-aider commands, we'll pipe the prompt
    local full_command
    case $ai in
        aider)
            full_command="cd '$project' && $ai_cmd"
            ;;
        *)
            # Create a temp file with the prompt for piping
            local prompt_file="/tmp/delegate_prompt_$$.txt"
            echo "$prompt" > "$prompt_file"
            full_command="cd '$project' && cat '$prompt_file' | $ai_cmd; rm -f '$prompt_file'"
            ;;
    esac

    # Use AppleScript to open a new split in Ghostty
    osascript << EOF
tell application "Ghostty"
    activate
end tell

delay 0.3

tell application "System Events"
    tell process "Ghostty"
        set frontmost to true

        -- Create new split to the right (Cmd+D)
        keystroke "d" using command down
        delay 0.5

        -- Type the command (using clipboard for reliability)
        set the clipboard to "$full_command"
        delay 0.1
        keystroke "v" using command down
        delay 0.2

        -- Execute it
        keystroke return
    end tell
end tell
EOF

    return $?
}

#══════════════════════════════════════════════════════════════════════════════
# Main
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}Opening interactive delegation pane...${NC}"
echo -e "${DIM}AI: $AI_NAME${NC}"
echo -e "${DIM}Project: $PROJECT_NAME${NC}"

# Build enhanced prompt
ENHANCED_PROMPT=$(build_enhanced_prompt "$TASK_DESC" "$PROJECT_PATH")

# Open Ghostty and run
if open_ghostty_delegate "$AI_NAME" "$ENHANCED_PROMPT" "$PROJECT_PATH"; then
    echo -e "${GREEN}✓${NC} Delegation pane opened"
    echo -e "${DIM}The AI is now working in a split pane to the right${NC}"

    # Generate task ID for tracking
    TASK_ID="${AI_NAME}_interactive_$(date +%Y%m%d_%H%M%S)_$$"
    echo "{\"task_id\": \"$TASK_ID\", \"status\": \"interactive\", \"ai\": \"$AI_NAME\", \"project\": \"$PROJECT_PATH\"}"
else
    echo -e "${RED}✗${NC} Failed to open delegation pane"
    exit 1
fi
