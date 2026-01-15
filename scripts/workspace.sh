#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  AI WORKSPACE LAUNCHER
#══════════════════════════════════════════════════════════════════════════════
#
#  DESCRIPTION:
#    Opens a project in Ghostty with a split-pane workspace:
#    - Left pane: Claude Code
#    - Right panes: Dev processes defined in .claude-workspace.json
#
#  USAGE:
#    workspace.sh <project_path>
#    workspace.sh                    # Uses current directory
#    workspace.sh --help
#
#  CONFIG FILE (.claude-workspace.json):
#    Place in your project root. Example:
#    {
#      "processes": [
#        {"name": "frontend", "command": "npm run dev"},
#        {"name": "backend", "command": "cargo watch -x run"}
#      ]
#    }
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
#  REQUIREMENTS:
#    - Ghostty terminal
#    - jq (brew install jq)
#    - macOS (uses AppleScript)
#
#══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$HOME/.claude-workspace/scripts"

# Source libraries
if [ -f "$SCRIPT_DIR/lib/tldr.sh" ]; then
    source "$SCRIPT_DIR/lib/tldr.sh"
fi

if [ -f "$SCRIPT_DIR/lib/workspace-instructions.sh" ]; then
    source "$SCRIPT_DIR/lib/workspace-instructions.sh"
fi

if [ -f "$SCRIPT_DIR/lib/feature-status.sh" ]; then
    source "$SCRIPT_DIR/lib/feature-status.sh"
fi

show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║  AI WORKSPACE LAUNCHER                                                       ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
  workspace.sh [project_path]     Open workspace for project
  workspace.sh                    Open workspace for current directory
  workspace.sh -h, --help         Show this help

CONFIG FILE (.claude-workspace.json):
  Place in your project root to define dev processes:

  {
    "processes": [
      {"name": "frontend", "command": "npm run dev", "cwd": "./frontend"},
      {"name": "backend", "command": "cargo watch -x run"},
      {"name": "types", "command": "tsc --watch"}
    ],
    "hooks": {
      "before_start": "docker compose up -d"
    }
  }

LAYOUT:
  ┌─────────────────┬─────────────────┐
  │                 │   Process 1     │
  │     Claude      ├─────────────────┤
  │      Code       │   Process 2     │
  │                 ├─────────────────┤
  │                 │   Process 3     │
  └─────────────────┴─────────────────┘

PROCESS OPTIONS:
  name      Name for the process (used in dev-logs)
  command   Command to run
  cwd       Working directory (relative to project root)

FEATURES:
  - All dev processes wrapped with dev-run.sh for log capture
  - Claude can check logs with dev-logs.sh
  - Processes isolated per project
  - Hooks for setup/teardown commands

EOF
}

# Check for help
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
    show_help
    exit 0
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

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  AI WORKSPACE LAUNCHER                                                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Project: $PROJECT_NAME"
echo "Path: $PROJECT_PATH"
echo ""

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    echo "Install with: brew install jq"
    exit 1
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

# TLDR Integration - use the user-friendly setup script
if [ -f "$CONFIG_FILE" ]; then
    TLDR_ENABLED=$(echo "$CONFIG" | jq -r '.tldr.enabled // false')

    if [ "$TLDR_ENABLED" = "true" ]; then
        if [ -x "$SCRIPT_DIR/tldr-setup.sh" ]; then
            "$SCRIPT_DIR/tldr-setup.sh" "$PROJECT_PATH"
        else
            echo ""
            echo "TLDR Code Analysis"
            # Fallback to library functions
            if type warm_tldr_indexes &>/dev/null; then
                warm_tldr_indexes "$PROJECT_PATH"
                [ type configure_tldr_mcp &>/dev/null ] && configure_tldr_mcp "$PROJECT_PATH"
            else
                echo "  Warning: TLDR not available"
            fi
            echo ""
        fi
    fi
fi

# Workspace Instructions - Update CLAUDE.md with dev-logs instructions
if [ "$PROCESS_COUNT" -gt 0 ]; then
    if type update_workspace_instructions &>/dev/null; then
        CLAUDE_MD="$PROJECT_PATH/CLAUDE.md"
        # Always update to ensure latest emphatic instructions
        update_workspace_instructions "$PROJECT_PATH"
    fi
fi

# Show feature status with warnings
if type show_feature_status &>/dev/null; then
    show_feature_status "$PROJECT_PATH"
fi

# Build the process commands
PROCESS_COMMANDS=""
DEV_RUN="$HOME/.claude-workspace/scripts/dev-run.sh"

for i in $(seq 0 $(($PROCESS_COUNT - 1))); do
    NAME=$(echo "$CONFIG" | jq -r ".processes[$i].name")
    CMD=$(echo "$CONFIG" | jq -r ".processes[$i].command")
    CWD=$(echo "$CONFIG" | jq -r ".processes[$i].cwd // \".\"")

    # Build full command with cd and dev-run wrapper
    if [ "$CWD" = "." ]; then
        FULL_CMD="cd '$PROJECT_PATH' && '$DEV_RUN' '$NAME' $CMD"
    else
        FULL_CMD="cd '$PROJECT_PATH/$CWD' && '$DEV_RUN' '$NAME' $CMD"
    fi

    echo "  [$i] $NAME: $CMD"

    if [ -n "$PROCESS_COMMANDS" ]; then
        PROCESS_COMMANDS="$PROCESS_COMMANDS"$'\n'"$FULL_CMD"
    else
        PROCESS_COMMANDS="$FULL_CMD"
    fi
done

echo ""
echo "Launching Ghostty workspace..."
echo ""

# Set environment variables for AppleScript
export PROJECT_PATH
export CLAUDE_CMD="$SCRIPT_DIR/claude-workspace.sh '$PROJECT_PATH'"
export PROCESS_COMMANDS

# Run the AppleScript and capture errors
APPLESCRIPT_OUTPUT=$(osascript "$SCRIPT_DIR/ghostty-workspace.applescript" 2>&1)
APPLESCRIPT_EXIT=$?

if [ $APPLESCRIPT_EXIT -ne 0 ]; then
    if echo "$APPLESCRIPT_OUTPUT" | grep -q "not allowed to send keystrokes\|1002"; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║  ⚠️  ACCESSIBILITY PERMISSION REQUIRED                                        ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "macOS blocked the keyboard automation. To fix this:"
        echo ""
        echo "  1. Open System Settings → Privacy & Security → Accessibility"
        echo "  2. Click the lock icon 🔒 and enter your password"
        echo "  3. Click the + button"
        echo "  4. Navigate to /Applications and add 'Ghostty'"
        echo "  5. Make sure the checkbox next to Ghostty is ✓ enabled"
        echo "  6. RESTART Ghostty completely (Cmd+Q, then reopen)"
        echo ""
        echo "If Ghostty is already listed, try:"
        echo "  - Toggle it OFF and ON again"
        echo "  - Remove it and re-add it"
        echo "  - Restart your Mac"
        echo ""

        read -p "Open Accessibility Settings now? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        fi
        exit 1
    else
        echo "Error running AppleScript:"
        echo "$APPLESCRIPT_OUTPUT"
        exit 1
    fi
fi

echo "✓ Workspace launched!"
echo ""
echo "Tips:"
echo "  - Claude is in the left pane"
echo "  - Use Cmd+[ and Cmd+] to navigate between panes"
echo "  - Dev logs: ~/.claude-workspace/dev-logs/$PROJECT_NAME/"
