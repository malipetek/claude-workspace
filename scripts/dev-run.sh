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
#    4. Support restart with 'rs' command (like nodemon)
#
#  USAGE:
#    dev-run.sh <name> <command...>
#
#  RESTART:
#    Type 'rs' + Enter to restart the process without losing log sync
#    DO NOT manually Ctrl+C and re-run the command!
#
#  EXAMPLES:
#    dev-run.sh frontend npm run dev
#    dev-run.sh backend cargo watch -x run
#    dev-run.sh types tsc --watch
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
    local git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ]; then
        basename "$git_root"
    else
        basename "$(pwd)"
    fi
}

PROJECT=$(detect_project)
LOG_DIR="$HOME/.claude-workspace/dev-logs/$PROJECT"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/${NAME}.log"
PID_FILE="$LOG_DIR/${NAME}.pid"
INFO_FILE="$LOG_DIR/${NAME}.info"
RESTART_FILE="$LOG_DIR/${NAME}.restart"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

# Show startup banner
show_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}$NAME${NC} - Dev Process with Log Capture                                       "
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}rs${NC} + Enter  →  Restart process (keeps log sync)                            "
    echo -e "${CYAN}║${NC}  ${RED}Ctrl+C${NC}      →  Stop completely                                              "
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}⚠️  DO NOT manually stop and re-run the command!${NC}                            "
    echo -e "${CYAN}║${NC}  ${DIM}Use 'rs' to restart - this keeps Claude's log access working${NC}              "
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Write log header
write_log_header() {
    echo "=== Dev process '$NAME' starting ===" >> "$LOG_FILE"
    echo "Project: $PROJECT" >> "$LOG_FILE"
    echo "Command: $COMMAND" >> "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "CWD: $(pwd)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
}

# Write process info
write_info() {
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
}

# Show stop banner
show_stop_banner() {
    local reason="${1:-Stopped}"
    echo ""
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}$NAME${NC} - $reason"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}  Process has been terminated.                                                "
    echo -e "${RED}║${NC}  ${DIM}This window can be closed, or press any key to exit.${NC}                      "
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Kill a process tree recursively (children first)
kill_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Kill all children first (recursively)
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child" "$signal"
    done

    # Then kill the process itself
    kill -"$signal" "$pid" 2>/dev/null
}

# Wait for a process tree to fully die
wait_for_death() {
    local pid=$1
    local max_wait=${2:-5}
    local waited=0

    while [ $waited -lt $max_wait ]; do
        # Check if process or any children still exist
        if ! kill -0 "$pid" 2>/dev/null && [ -z "$(pgrep -P "$pid" 2>/dev/null)" ]; then
            return 0
        fi
        sleep 0.2
        waited=$((waited + 1))
    done

    return 1  # Still alive after max_wait
}

# Extract port from command string (e.g., --port 5173, -p 3000, :8080)
extract_port_from_command() {
    local cmd="$1"

    # Try --port NUMBER or -p NUMBER
    local port=$(echo "$cmd" | grep -oE '(--port|-p)[= ]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$port" ] && echo "$port" && return

    # Try PORT=NUMBER environment style
    port=$(echo "$cmd" | grep -oE 'PORT[= ]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$port" ] && echo "$port" && return

    # Try localhost:PORT or 127.0.0.1:PORT
    port=$(echo "$cmd" | grep -oE '(localhost|127\.0\.0\.1):[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$port" ] && echo "$port" && return
}

# Extract port from log file (look for "localhost:PORT" or "port PORT")
extract_port_from_log() {
    local log_file="$1"

    # Look for localhost:PORT pattern (common in vite, next, etc.)
    local port=$(tail -50 "$log_file" 2>/dev/null | grep -oE 'localhost:[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$port" ] && echo "$port" && return

    # Look for "port 5173" or "Port: 5173" pattern
    port=$(tail -50 "$log_file" 2>/dev/null | grep -ioE 'port[: ]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$port" ] && echo "$port" && return
}

# Scan common dev ports to find which ones are in use
find_common_dev_ports_in_use() {
    local common_ports="3000 3001 4000 5000 5173 5174 8000 8080 8888 9000"
    local in_use=""

    for port in $common_ports; do
        if lsof -ti:$port >/dev/null 2>&1; then
            in_use="$in_use $port"
        fi
    done

    echo "$in_use" | tr -s ' ' | sed 's/^ //'
}

# Get all PIDs in a process tree
get_all_pids() {
    local pid=$1
    echo "$pid"
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        get_all_pids "$child"
    done
}

# Get all listening ports used by a process tree
get_ports_for_pid() {
    local pid=$1
    local all_pids=$(get_all_pids "$pid" | tr '\n' ',' | sed 's/,$//')

    # Get ports for all PIDs at once
    local ports=""
    for p in $(echo "$all_pids" | tr ',' ' '); do
        local pid_ports=$(lsof -Pan -p "$p" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | grep -oE '[0-9]+$')
        [ -n "$pid_ports" ] && ports="$ports $pid_ports"
    done

    echo "$ports" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' '
}

# Wait for ports to be released
wait_for_ports() {
    local ports="$1"
    local max_wait=${2:-30}
    local waited=0

    [ -z "$ports" ] && return 0

    echo -e "${DIM}Waiting for ports to be released: $ports${NC}"

    while [ $waited -lt $max_wait ]; do
        local still_busy=""
        for port in $ports; do
            if lsof -ti:$port >/dev/null 2>&1; then
                still_busy="$still_busy $port"
            fi
        done

        if [ -z "$still_busy" ]; then
            echo -e "${DIM}All ports released${NC}"
            return 0
        fi

        sleep 0.3
        waited=$((waited + 1))

        # Show progress every second
        if [ $((waited % 3)) -eq 0 ]; then
            echo -e "${DIM}Still waiting for:$still_busy${NC}"
        fi
    done

    echo -e "${YELLOW}Warning: Ports still in use after ${max_wait}x0.3s:$still_busy${NC}"
    return 1
}

# Cleanup on exit
cleanup() {
    rm -f "$PID_FILE"
    rm -f "$RESTART_FILE"
    # Kill input reader if running
    [ -n "$INPUT_READER_PID" ] && kill $INPUT_READER_PID 2>/dev/null
    # Kill command tree if running
    [ -n "$CMD_PID" ] && kill_tree $CMD_PID 2>/dev/null
    echo "" >> "$LOG_FILE"
    echo "=== Process '$NAME' stopped: $(date) ===" >> "$LOG_FILE"
}
trap cleanup EXIT

# Handle SIGTERM (from workspace cleanup) - kill child, show banner, wait for key
handle_term() {
    # Kill child process tree if running
    if [ -n "$CMD_PID" ] && kill -0 $CMD_PID 2>/dev/null; then
        kill_tree $CMD_PID TERM
        wait_for_death $CMD_PID 5
        # Force kill if still alive
        if kill -0 $CMD_PID 2>/dev/null; then
            kill_tree $CMD_PID KILL
        fi
    fi
    # Close FIFO
    exec 3>&- 2>/dev/null
    # Show banner
    show_stop_banner "Claude workspace closed"
    # Wait for keypress (reset terminal first)
    stty sane 2>/dev/null
    read -n 1 -s -r 2>/dev/null
    exit 0
}
trap handle_term TERM

# Handle Ctrl+C gracefully - kill child, show banner (no wait - user initiated)
handle_int() {
    # Kill child process tree if running
    if [ -n "$CMD_PID" ] && kill -0 $CMD_PID 2>/dev/null; then
        kill_tree $CMD_PID TERM
        wait_for_death $CMD_PID 3
        # Force kill if still alive
        if kill -0 $CMD_PID 2>/dev/null; then
            kill_tree $CMD_PID KILL
        fi
    fi
    # Close FIFO
    exec 3>&- 2>/dev/null
    # Show banner (no wait for Ctrl+C since user initiated it)
    show_stop_banner "Interrupted (Ctrl+C)"
    exit 0
}
trap handle_int INT

# Show the banner
show_banner

echo -e "${DIM}📋 Logging to: $LOG_FILE${NC}"
echo ""

# Main restart loop
FIRST_RUN=true

while true; do
    rm -f "$RESTART_FILE"
    CAPTURED_PORTS=""

    # Clear log on start (fresh session)
    if [ "$FIRST_RUN" = true ]; then
        > "$LOG_FILE"
        FIRST_RUN=false
    else
        # On restart, add separator but don't clear
        echo "" >> "$LOG_FILE"
        echo "=== RESTARTED: $(date) ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi

    write_log_header
    write_info

    # Run command with NO stdin (prevents it from stealing our input)
    $COMMAND </dev/null 2>&1 | tee -a "$LOG_FILE" &
    CMD_PID=$!
    # Store OUR PID (dev-run.sh) so cleanup can signal us properly
    echo $$ > "$PID_FILE"

    # Read from terminal, watch for 'rs' + Enter
    RESTART_REQUESTED=false

    while kill -0 $CMD_PID 2>/dev/null; do
        # Read line with timeout
        if IFS= read -r -t 1 line </dev/tty 2>/dev/null; then
            if [ "$line" = "rs" ]; then
                RESTART_REQUESTED=true
                echo ""
                echo -e "${YELLOW}⏳ Stopping process...${NC}"

                # FIRST: Capture ports BEFORE killing (while processes still exist)
                # Try multiple methods in order of reliability

                # Method 1: Get ports from process tree via lsof
                CAPTURED_PORTS=$(get_ports_for_pid $CMD_PID)

                # Method 2: Extract from log file (vite prints "localhost:5173")
                if [ -z "$(echo "$CAPTURED_PORTS" | tr -d ' ')" ]; then
                    LOG_PORT=$(extract_port_from_log "$LOG_FILE")
                    if [ -n "$LOG_PORT" ]; then
                        CAPTURED_PORTS="$LOG_PORT"
                        echo -e "${DIM}Port from log: $CAPTURED_PORTS${NC}"
                    fi
                fi

                # Method 3: Extract from command string
                if [ -z "$(echo "$CAPTURED_PORTS" | tr -d ' ')" ]; then
                    CMD_PORT=$(extract_port_from_command "$COMMAND")
                    if [ -n "$CMD_PORT" ]; then
                        CAPTURED_PORTS="$CMD_PORT"
                        echo -e "${DIM}Port from command: $CAPTURED_PORTS${NC}"
                    fi
                fi

                # Method 4: Scan common dev ports
                if [ -z "$(echo "$CAPTURED_PORTS" | tr -d ' ')" ]; then
                    COMMON_PORTS=$(find_common_dev_ports_in_use)
                    if [ -n "$COMMON_PORTS" ]; then
                        CAPTURED_PORTS="$COMMON_PORTS"
                        echo -e "${DIM}Common ports in use: $CAPTURED_PORTS${NC}"
                    fi
                fi

                if [ -n "$(echo "$CAPTURED_PORTS" | tr -d ' ')" ]; then
                    echo -e "${DIM}Will wait for ports: $CAPTURED_PORTS${NC}"
                else
                    echo -e "${YELLOW}Warning: Could not detect ports${NC}"
                fi

                # Kill processes holding the ports directly (most reliable method)
                for port in $CAPTURED_PORTS; do
                    port=$(echo "$port" | tr -d ' ')
                    [ -z "$port" ] && continue
                    echo -e "${DIM}Killing processes on port $port...${NC}"
                    kill -9 $(lsof -ti:$port) 2>/dev/null
                done

                # Also kill our process tree for good measure
                kill_tree $CMD_PID KILL 2>/dev/null

                # Brief wait
                sleep 0.3
                break
            fi
        fi
    done

    # Handle restart
    if [ "$RESTART_REQUESTED" = true ]; then
        # Wait for ports to be released (shorter timeout after SIGKILL)
        if [ -n "$CAPTURED_PORTS" ]; then
            wait_for_ports "$CAPTURED_PORTS" 20
        fi

        echo ""
        echo -e "${CYAN}🔄 Restarting $NAME...${NC}"
        echo ""
        continue
    fi

    # Wait for process to fully exit (only if natural exit)
    wait $CMD_PID 2>/dev/null
    EXIT_CODE=$?

    # Process exited on its own (crash or Ctrl+C)
    break
done

exit $EXIT_CODE
