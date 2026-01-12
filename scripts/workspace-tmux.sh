#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  AI WORKSPACE LAUNCHER (TMUX VERSION)
#══════════════════════════════════════════════════════════════════════════════
#
#  DESCRIPTION:
#    Opens a project in a tmux session with split panes:
#    - Left pane: Claude Code
#    - Right panes: Dev processes defined in .claude-workspace.json
#
#  USAGE:
#    workspace-tmux.sh <project_path>
#    workspace-tmux.sh                    # Uses current directory
#
#  REQUIREMENTS:
#    - tmux (brew install tmux)
#    - jq (brew install jq)
#
#  LAYOUT:
#    ┌─────────────────┬─────────────────┐
#    │                 │    frontend     │
#    │     Claude      ├─────────────────┤
#    │      Code       │    backend      │
#    │                 ├─────────────────┤
#    │                 │     types       │
#    └─────────────────┴─────────────────┘
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"

show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║  AI WORKSPACE LAUNCHER (TMUX)                                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
  workspace-tmux.sh [project_path]   Open workspace for project
  workspace-tmux.sh                  Open workspace for current directory
  workspace-tmux.sh -h, --help       Show this help

LAYOUT:
  ┌─────────────────┬─────────────────┐
  │                 │   Process 1     │
  │     Claude      ├─────────────────┤
  │      Code       │   Process 2     │
  │                 ├─────────────────┤
  │                 │   Process 3     │
  └─────────────────┴─────────────────┘

TMUX SHORTCUTS:
  Ctrl+b then arrow   Navigate between panes
  Ctrl+b then z       Zoom current pane (toggle fullscreen)
  Ctrl+b then d       Detach from session
  Ctrl+b then x       Close current pane

REATTACH:
  tmux attach -t <project-name>

EOF
}

# Check for help
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
    show_help
    exit 0
fi

# Check for tmux
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is required"
    echo "Install with: brew install tmux"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    echo "Install with: brew install jq"
    exit 1
fi

# Determine project path
if [ -n "$1" ]; then
    PROJECT_PATH="$1"
else
    PROJECT_PATH="$(pwd)"
fi

# Resolve to absolute path
PROJECT_PATH="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)"

if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: Directory not found: $PROJECT_PATH"
    exit 1
fi

CONFIG_FILE="$PROJECT_PATH/.claude-workspace.json"
PROJECT_NAME=$(basename "$PROJECT_PATH")
SESSION_NAME="ai-${PROJECT_NAME}"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  AI WORKSPACE LAUNCHER (TMUX)                                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Project: $PROJECT_NAME"
echo "Path: $PROJECT_PATH"
echo "Session: $SESSION_NAME"
echo ""

# Check if session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Session '$SESSION_NAME' already exists."
    echo ""
    read -p "Attach to existing session? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Killing existing session..."
        tmux kill-session -t "$SESSION_NAME"
    else
        echo "Attaching..."
        exec tmux attach -t "$SESSION_NAME"
    fi
fi

# Load config or use defaults
if [ -f "$CONFIG_FILE" ]; then
    echo "Config: $CONFIG_FILE"
    CONFIG=$(cat "$CONFIG_FILE")

    # Run before_start hook if defined
    BEFORE_HOOK=$(echo "$CONFIG" | jq -r '.hooks.before_start // empty')
    if [ -n "$BEFORE_HOOK" ]; then
        echo "Running before_start hook..."
        (cd "$PROJECT_PATH" && eval "$BEFORE_HOOK")
    fi

    # Extract processes
    PROCESS_COUNT=$(echo "$CONFIG" | jq '.processes | length')
    echo "Dev processes: $PROCESS_COUNT"
    echo ""
else
    echo "No .claude-workspace.json found, launching Claude only"
    PROCESS_COUNT=0
    CONFIG="{}"
fi

DEV_RUN="$HOME/.claude-workspace/scripts/dev-run.sh"

# Create new tmux session with Claude in the first pane
echo "Creating tmux session..."
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_PATH" -x "$(tput cols)" -y "$(tput lines)"

# Rename the window
tmux rename-window -t "$SESSION_NAME" "workspace"

# Start Claude in the first pane
tmux send-keys -t "$SESSION_NAME" "claude" Enter

if [ "$PROCESS_COUNT" -gt 0 ]; then
    # Create right split for first process
    tmux split-window -h -t "$SESSION_NAME" -c "$PROJECT_PATH"

    # Get first process info
    NAME=$(echo "$CONFIG" | jq -r ".processes[0].name")
    CMD=$(echo "$CONFIG" | jq -r ".processes[0].command")
    CWD=$(echo "$CONFIG" | jq -r ".processes[0].cwd // \".\"")

    echo "  [1] $NAME: $CMD"

    if [ "$CWD" = "." ]; then
        FULL_PATH="$PROJECT_PATH"
    else
        FULL_PATH="$PROJECT_PATH/$CWD"
    fi

    tmux send-keys -t "$SESSION_NAME" "cd '$FULL_PATH' && '$DEV_RUN' '$NAME' $CMD" Enter

    # Add remaining processes as vertical splits in the right column
    for i in $(seq 1 $(($PROCESS_COUNT - 1))); do
        NAME=$(echo "$CONFIG" | jq -r ".processes[$i].name")
        CMD=$(echo "$CONFIG" | jq -r ".processes[$i].command")
        CWD=$(echo "$CONFIG" | jq -r ".processes[$i].cwd // \".\"")

        echo "  [$((i+1))] $NAME: $CMD"

        if [ "$CWD" = "." ]; then
            FULL_PATH="$PROJECT_PATH"
        else
            FULL_PATH="$PROJECT_PATH/$CWD"
        fi

        # Split the current pane vertically (down)
        tmux split-window -v -t "$SESSION_NAME" -c "$FULL_PATH"
        tmux send-keys -t "$SESSION_NAME" "cd '$FULL_PATH' && '$DEV_RUN' '$NAME' $CMD" Enter
    done

    # Balance the right panes
    tmux select-layout -t "$SESSION_NAME" main-vertical

    # Resize left pane (Claude) to 50%
    tmux resize-pane -t "$SESSION_NAME:0.0" -x 50%
fi

# Select the Claude pane (leftmost)
tmux select-pane -t "$SESSION_NAME:0.0"

echo ""
echo "✓ Workspace created!"
echo ""
echo "Tmux shortcuts:"
echo "  Ctrl+b →     Move to right pane"
echo "  Ctrl+b ←     Move to left pane"
echo "  Ctrl+b ↑/↓   Move up/down in right column"
echo "  Ctrl+b z     Zoom current pane (toggle)"
echo "  Ctrl+b d     Detach (session keeps running)"
echo ""
echo "Reattach later: tmux attach -t $SESSION_NAME"
echo ""

# Attach to the session
exec tmux attach -t "$SESSION_NAME"
