#!/bin/bash

# Check Status of Delegated Tasks
# Usage: ./check-status.sh [task_id|all|running|recent]

QUERY=$1
STATUS_DIR="$HOME/.claude-workspace/status"

if [ ! -d "$STATUS_DIR" ]; then
    echo "No status directory found. No tasks have been delegated yet."
    exit 0
fi

show_task() {
    local file=$1
    if [ -f "$file" ]; then
        cat "$file"
        echo ""
    fi
}

case $QUERY in
    ""|all)
        echo "=== All Delegated Tasks ==="
        for f in "$STATUS_DIR"/*.status 2>/dev/null; do
            [ -f "$f" ] && show_task "$f"
        done
        ;;
    running)
        echo "=== Running Tasks ==="
        for f in "$STATUS_DIR"/*.status 2>/dev/null; do
            if [ -f "$f" ] && grep -q '"status": "running"' "$f"; then
                show_task "$f"
            fi
        done
        ;;
    recent)
        echo "=== Recent Tasks (last 10) ==="
        ls -t "$STATUS_DIR"/*.status 2>/dev/null | head -10 | while read f; do
            show_task "$f"
        done
        ;;
    clean)
        echo "Cleaning completed/failed task statuses..."
        CLEANED=0
        for f in "$STATUS_DIR"/*.status 2>/dev/null; do
            if [ -f "$f" ]; then
                if grep -q '"status": "completed"\|"status": "failed"' "$f"; then
                    rm "$f"
                    ((CLEANED++))
                fi
            fi
        done
        echo "Cleaned $CLEANED status files"
        ;;
    *)
        # Treat as task_id
        STATUS_FILE="$STATUS_DIR/${QUERY}.status"
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            # Try partial match
            MATCHES=$(ls "$STATUS_DIR"/*"$QUERY"*.status 2>/dev/null)
            if [ -n "$MATCHES" ]; then
                for f in $MATCHES; do
                    show_task "$f"
                done
            else
                echo "No task found matching: $QUERY"
                exit 1
            fi
        fi
        ;;
esac
