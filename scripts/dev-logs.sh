#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  DEV LOGS READER
#══════════════════════════════════════════════════════════════════════════════
#
#  DESCRIPTION:
#    Read dev process logs to find errors, check status, and monitor output.
#    Used by Claude to check for errors instead of running redundant builds.
#
#  USAGE:
#    dev-logs.sh [command] [args]
#
#  COMMANDS:
#    list                    - List all dev processes with logs
#    summary                 - Quick summary of all dev process status (default)
#    tail <name> [n]         - Show last n lines (default 50) from a log
#    errors [name]           - Extract error lines (all projects or specific)
#    recent [n]              - Recent errors (last n lines, default 100)
#    watch <name>            - Show new lines since last check
#    clear <name>            - Clear a dev log
#    projects                - List all projects with dev logs
#
#  PROJECT DETECTION:
#    The script auto-detects your current project from git root.
#    Logs are stored in: ~/.claude-workspace/dev-logs/<project>/<name>.log
#
#    To check logs for a specific project, set DEV_PROJECT env var:
#      DEV_PROJECT=my-app dev-logs.sh summary
#
#  EXAMPLES:
#    dev-logs.sh summary              # Check current project for errors
#    dev-logs.sh errors               # Show all errors in current project
#    dev-logs.sh errors frontend      # Errors from frontend process
#    dev-logs.sh tail backend 100     # Last 100 lines from backend
#    dev-logs.sh projects             # List all projects with logs
#    DEV_PROJECT=other-app dev-logs.sh summary  # Check different project
#
#══════════════════════════════════════════════════════════════════════════════

BASE_LOG_DIR="$HOME/.claude-workspace/dev-logs"
MARKER_DIR="$HOME/.claude-workspace/dev-markers"
mkdir -p "$MARKER_DIR"

# Detect project from git root or current directory
detect_project() {
    # Allow override via environment variable
    if [ -n "$DEV_PROJECT" ]; then
        echo "$DEV_PROJECT"
        return
    fi

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
LOG_DIR="$BASE_LOG_DIR/$PROJECT"

# Common error patterns for various tools
ERROR_PATTERNS="error|Error|ERROR|failed|Failed|FAILED|exception|Exception|EXCEPTION|panic|PANIC|fatal|Fatal|FATAL|warning|Warning|WARN|\berr\b|Cannot|cannot|undefined|Undefined|null|TypeError|SyntaxError|ReferenceError|CompileError|ParseError|ENOENT|EACCES|EPERM|segfault|Segmentation|TS[0-9]+:|ESLint|error\[E[0-9]+\]"

cmd_projects() {
    echo "=== Projects with Dev Logs ==="
    echo ""
    for proj_dir in "$BASE_LOG_DIR"/*/; do
        [ -d "$proj_dir" ] || continue
        PROJ_NAME=$(basename "$proj_dir")
        LOG_COUNT=$(ls "$proj_dir"/*.log 2>/dev/null | wc -l | tr -d ' ')
        TOTAL_ERRORS=0

        for log in "$proj_dir"/*.log; do
            [ -f "$log" ] 2>/dev/null || continue
            ERRORS=$(grep -c -E "$ERROR_PATTERNS" "$log" 2>/dev/null | head -1 || echo 0)
        ERRORS=${ERRORS:-0}
            TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))
        done

        if [ "$PROJ_NAME" = "$PROJECT" ]; then
            echo "▶ $PROJ_NAME (current)"
        else
            echo "  $PROJ_NAME"
        fi
        echo "    Processes: $LOG_COUNT | Total errors: $TOTAL_ERRORS"
        echo ""
    done
}

cmd_list() {
    echo "=== Dev Logs for: $PROJECT ==="
    echo ""

    if [ ! -d "$LOG_DIR" ]; then
        echo "No logs found for project: $PROJECT"
        echo "Start dev processes with: dev-run.sh <name> <command>"
        echo ""
        echo "Use 'dev-logs.sh projects' to see all projects with logs"
        return
    fi

    for info in "$LOG_DIR"/*.info ; do
        [ -f "$info" ] || continue
        NAME=$(basename "$info" .info)
        LOG_FILE="$LOG_DIR/${NAME}.log"

        if [ -f "$LOG_FILE" ]; then
            LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
            SIZE=$(du -h "$LOG_FILE" | cut -f1)
            ERRORS=$(grep -cE "$ERROR_PATTERNS" "$LOG_FILE" 2>/dev/null || echo 0)
            LAST_MOD=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LOG_FILE" 2>/dev/null || stat -c "%y" "$LOG_FILE" 2>/dev/null | cut -d. -f1)

            # Check if process might still be running
            if [ -f "$LOG_DIR/${NAME}.pid" ]; then
                STATUS="[RUNNING]"
            else
                STATUS="[STOPPED]"
            fi

            echo "$NAME $STATUS"
            echo "  Lines: $LINES | Size: $SIZE | Errors: $ERRORS"
            echo "  Last update: $LAST_MOD"
            echo ""
        fi
    done
}

cmd_tail() {
    NAME=$1
    LINES=${2:-50}
    LOG_FILE="$LOG_DIR/${NAME}.log"

    if [ ! -f "$LOG_FILE" ]; then
        echo "No log found for: $NAME in project $PROJECT"
        echo "Available: $(ls "$LOG_DIR"/*.log 2>/dev/null | xargs -I {} basename {} .log | tr '\n' ' ')"
        return 1
    fi

    echo "=== Last $LINES lines from $PROJECT/$NAME ==="
    tail -n "$LINES" "$LOG_FILE"
}

cmd_errors() {
    NAME=$1

    if [ -n "$NAME" ]; then
        # Specific process
        LOG_FILE="$LOG_DIR/${NAME}.log"
        if [ ! -f "$LOG_FILE" ]; then
            echo "No log found for: $NAME"
            return 1
        fi
        echo "=== Errors from $PROJECT/$NAME ==="
        grep -n -E "$ERROR_PATTERNS" "$LOG_FILE" | tail -100
    else
        # All processes in current project
        echo "=== Errors from $PROJECT ==="
        echo ""
        for log in "$LOG_DIR"/*.log ; do
            [ -f "$log" ] || continue
            NAME=$(basename "$log" .log)
            ERRORS=$(grep -c -E "$ERROR_PATTERNS" "$log" 2>/dev/null | head -1 || echo 0)
        ERRORS=${ERRORS:-0}

            if [ "$ERRORS" -gt 0 ]; then
                echo "--- $NAME ($ERRORS errors) ---"
                grep -n -E "$ERROR_PATTERNS" "$log" | tail -20
                echo ""
            fi
        done
    fi
}

cmd_watch() {
    NAME=$1
    LOG_FILE="$LOG_DIR/${NAME}.log"
    MARKER_FILE="$MARKER_DIR/${PROJECT}_${NAME}.marker"

    if [ ! -f "$LOG_FILE" ]; then
        echo "No log found for: $NAME"
        return 1
    fi

    CURRENT_LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')

    if [ -f "$MARKER_FILE" ]; then
        LAST_LINES=$(cat "$MARKER_FILE")
    else
        LAST_LINES=0
    fi

    if [ "$CURRENT_LINES" -gt "$LAST_LINES" ]; then
        NEW_LINES=$((CURRENT_LINES - LAST_LINES))
        echo "=== $NEW_LINES new lines in $PROJECT/$NAME ==="
        tail -n "$NEW_LINES" "$LOG_FILE"
    else
        echo "No new output in $PROJECT/$NAME since last check"
    fi

    # Update marker
    echo "$CURRENT_LINES" > "$MARKER_FILE"
}

cmd_summary() {
    echo "=== Dev Process Summary: $PROJECT ==="
    echo ""

    if [ ! -d "$LOG_DIR" ]; then
        echo "No dev logs for this project yet."
        echo "Start dev processes with: dev-run.sh <name> <command>"
        return
    fi

    TOTAL_ERRORS=0
    HAS_LOGS=false

    for log in "$LOG_DIR"/*.log ; do
        [ -f "$log" ] || continue
        HAS_LOGS=true
        NAME=$(basename "$log" .log)
        ERRORS=$(grep -c -E "$ERROR_PATTERNS" "$log" 2>/dev/null | head -1 || echo 0)
        ERRORS=${ERRORS:-0}
        TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))

        # Get last significant line (non-empty, non-separator)
        LAST_LINE=$(grep -v "^[=\-]*$" "$log" | grep -v "^$" | tail -1 | head -c 100)

        if [ "$ERRORS" -gt 0 ]; then
            echo "❌ $NAME: $ERRORS errors"
        else
            echo "✓ $NAME: OK"
        fi
        echo "   Last: $LAST_LINE"
        echo ""
    done

    if [ "$HAS_LOGS" = false ]; then
        echo "No dev logs found. Start with: dev-run.sh <name> <command>"
        return
    fi

    echo "---"
    echo "Total errors: $TOTAL_ERRORS"

    if [ "$TOTAL_ERRORS" -gt 0 ]; then
        echo ""
        echo "Run 'dev-logs.sh errors' to see error details"
    fi
}

cmd_clear() {
    NAME=$1
    LOG_FILE="$LOG_DIR/${NAME}.log"
    MARKER_FILE="$MARKER_DIR/${PROJECT}_${NAME}.marker"

    if [ -f "$LOG_FILE" ]; then
        > "$LOG_FILE"
        rm -f "$MARKER_FILE"
        echo "Cleared log for: $PROJECT/$NAME"
    else
        echo "No log found for: $NAME"
    fi
}

cmd_recent() {
    # Get errors from the last N lines of all logs
    LINES=${1:-100}
    echo "=== Recent Errors in $PROJECT (last $LINES lines per log) ==="
    echo ""

    for log in "$LOG_DIR"/*.log ; do
        [ -f "$log" ] || continue
        NAME=$(basename "$log" .log)

        RECENT_ERRORS=$(tail -n "$LINES" "$log" | grep -E "$ERROR_PATTERNS")
        if [ -n "$RECENT_ERRORS" ]; then
            echo "--- $NAME ---"
            echo "$RECENT_ERRORS"
            echo ""
        fi
    done
}

# Main command dispatch
case ${1:-summary} in
    projects)
        cmd_projects
        ;;
    list)
        cmd_list
        ;;
    tail)
        cmd_tail "$2" "$3"
        ;;
    errors)
        cmd_errors "$2"
        ;;
    recent)
        cmd_recent "$2"
        ;;
    watch)
        cmd_watch "$2"
        ;;
    summary)
        cmd_summary
        ;;
    clear)
        cmd_clear "$2"
        ;;
    -h|--help|help)
        echo "Usage: dev-logs.sh [command] [args]"
        echo ""
        echo "Current project: $PROJECT"
        echo "Log directory: $LOG_DIR"
        echo ""
        echo "Commands:"
        echo "  summary             - Quick summary of dev process status (default)"
        echo "  list                - List all dev processes with details"
        echo "  projects            - List all projects with dev logs"
        echo "  tail <name> [n]     - Show last n lines (default 50)"
        echo "  errors [name]       - Extract error lines"
        echo "  recent [n]          - Recent errors (last n lines, default 100)"
        echo "  watch <name>        - Show new lines since last check"
        echo "  clear <name>        - Clear a dev log"
        echo ""
        echo "Environment:"
        echo "  DEV_PROJECT=<name>  - Override auto-detected project"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'dev-logs.sh help' for usage"
        exit 1
        ;;
esac
