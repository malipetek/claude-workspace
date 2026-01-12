#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  MENU LIBRARY - Flicker-free terminal menus
#══════════════════════════════════════════════════════════════════════════════
#
#  Provides consistent, flicker-free arrow-key navigation for menus.
#  Uses cursor positioning instead of screen clearing.
#
#  USAGE:
#    source ~/.claude-workspace/scripts/lib/menu.sh
#
#    menu_init "Title"
#    menu_add_item "item1" "Label 1" "Description 1"
#    menu_add_item "item2" "Label 2" "Description 2"
#    menu_add_separator
#    menu_add_item "quit" "Quit" "Exit the menu"
#
#    menu_run
#    echo "Selected: $MENU_RESULT"
#
#══════════════════════════════════════════════════════════════════════════════

# Colors
MENU_COLOR_RESET='\033[0m'
MENU_COLOR_BOLD='\033[1m'
MENU_COLOR_DIM='\033[2m'
MENU_COLOR_CYAN='\033[0;36m'
MENU_COLOR_GREEN='\033[0;32m'
MENU_COLOR_YELLOW='\033[1;33m'
MENU_COLOR_GRAY='\033[0;90m'
MENU_COLOR_BG_GREEN='\033[42m'
MENU_COLOR_FG_BLACK='\033[30m'

# State
MENU_TITLE=""
MENU_ITEMS=()
MENU_IDS=()
MENU_DESCRIPTIONS=()
MENU_TYPES=()  # "item" or "separator"
MENU_SELECTED=0
MENU_RESULT=""
MENU_HEADER_LINES=0
MENU_HINT="↑/↓: Navigate   Enter: Select   q: Quit"

# Terminal state
MENU_ROWS=0
MENU_COLS=0

# Initialize menu
menu_init() {
    MENU_TITLE="$1"
    MENU_ITEMS=()
    MENU_IDS=()
    MENU_DESCRIPTIONS=()
    MENU_TYPES=()
    MENU_SELECTED=0
    MENU_RESULT=""

    # Get terminal size
    MENU_ROWS=$(tput lines)
    MENU_COLS=$(tput cols)
}

# Add a menu item
menu_add_item() {
    local id="$1"
    local label="$2"
    local description="${3:-}"

    MENU_IDS+=("$id")
    MENU_ITEMS+=("$label")
    MENU_DESCRIPTIONS+=("$description")
    MENU_TYPES+=("item")
}

# Add a separator
menu_add_separator() {
    local label="${1:-}"
    MENU_IDS+=("")
    MENU_ITEMS+=("$label")
    MENU_DESCRIPTIONS+=("")
    MENU_TYPES+=("separator")
}

# Set custom hint text
menu_set_hint() {
    MENU_HINT="$1"
}

# Move cursor to position
menu_goto() {
    local row=$1
    local col=${2:-1}
    printf '\033[%d;%dH' "$row" "$col"
}

# Clear current line from cursor
menu_clear_line() {
    printf '\033[K'
}

# Clear from cursor to end of screen
menu_clear_below() {
    printf '\033[J'
}

# Hide cursor
menu_hide_cursor() {
    printf '\033[?25l'
}

# Show cursor
menu_show_cursor() {
    printf '\033[?25h'
}

# Enter alternate screen
menu_enter_alt_screen() {
    tput smcup 2>/dev/null || printf '\033[?1049h'
}

# Exit alternate screen
menu_exit_alt_screen() {
    tput rmcup 2>/dev/null || printf '\033[?1049l'
}

# Draw header (only once)
menu_draw_header() {
    menu_goto 1 1

    # Title box
    echo -e "${MENU_COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${MENU_COLOR_RESET}"
    echo -e "${MENU_COLOR_CYAN}║${MENU_COLOR_RESET}  ${MENU_COLOR_GREEN}${MENU_TITLE}${MENU_COLOR_RESET}"
    echo -e "${MENU_COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${MENU_COLOR_RESET}"
    echo ""
    echo -e "  ${MENU_COLOR_DIM}${MENU_HINT}${MENU_COLOR_RESET}"
    echo ""

    MENU_HEADER_LINES=6
}

# Draw a single menu item at a specific row
menu_draw_item() {
    local index=$1
    local row=$((MENU_HEADER_LINES + 1 + index * 2))  # 2 lines per item (label + description)

    local id="${MENU_IDS[$index]}"
    local label="${MENU_ITEMS[$index]}"
    local desc="${MENU_DESCRIPTIONS[$index]}"
    local type="${MENU_TYPES[$index]}"

    menu_goto $row 1
    menu_clear_line

    if [ "$type" = "separator" ]; then
        echo -e "  ${MENU_COLOR_GRAY}─────────────────────────────────────────────────────────────────────────────${MENU_COLOR_RESET}"
        menu_goto $((row + 1)) 1
        menu_clear_line
        if [ -n "$label" ]; then
            echo -e "  ${MENU_COLOR_GRAY}${label}${MENU_COLOR_RESET}"
        fi
        return
    fi

    if [ $index -eq $MENU_SELECTED ]; then
        # Selected item - highlighted
        echo -e " ${MENU_COLOR_BG_GREEN}${MENU_COLOR_FG_BLACK}▶ ${label}${MENU_COLOR_RESET}"
        menu_goto $((row + 1)) 1
        menu_clear_line
        if [ -n "$desc" ]; then
            echo -e "   ${MENU_COLOR_DIM}${desc}${MENU_COLOR_RESET}"
        fi
    else
        # Normal item
        echo -e "   ${label}"
        menu_goto $((row + 1)) 1
        menu_clear_line
        # Don't show description for non-selected items (cleaner look)
    fi
}

# Draw all menu items
menu_draw_items() {
    local total=${#MENU_ITEMS[@]}
    for ((i=0; i<total; i++)); do
        menu_draw_item $i
    done

    # Clear any remaining lines
    local end_row=$((MENU_HEADER_LINES + 1 + total * 2))
    menu_goto $end_row 1
    menu_clear_below
}

# Redraw only the items that changed (previous and current selection)
menu_redraw_changed() {
    local prev=$1
    local curr=$2

    # Redraw previous (now unselected)
    menu_draw_item $prev

    # Redraw current (now selected)
    menu_draw_item $curr
}

# Skip separators when navigating
menu_skip_separator() {
    local direction=$1
    local total=${#MENU_ITEMS[@]}

    while [ "${MENU_TYPES[$MENU_SELECTED]}" = "separator" ]; do
        if [ "$direction" = "down" ]; then
            ((MENU_SELECTED++))
            [ $MENU_SELECTED -ge $total ] && MENU_SELECTED=0
        else
            ((MENU_SELECTED--))
            [ $MENU_SELECTED -lt 0 ] && MENU_SELECTED=$((total - 1))
        fi
    done
}

# Main menu loop
menu_run() {
    local total=${#MENU_ITEMS[@]}

    if [ $total -eq 0 ]; then
        MENU_RESULT=""
        return 1
    fi

    # Setup
    menu_enter_alt_screen
    menu_hide_cursor

    # Cleanup on exit
    trap 'menu_show_cursor; menu_exit_alt_screen' EXIT

    # Initial skip of separators
    menu_skip_separator "down"

    # Draw everything once
    menu_draw_header
    menu_draw_items

    # Main loop
    while true; do
        read -rsn1 key

        local prev_selected=$MENU_SELECTED

        case "$key" in
            q|Q)
                MENU_RESULT=""
                menu_show_cursor
                menu_exit_alt_screen
                trap - EXIT
                return 1
                ;;
            "")  # Enter
                MENU_RESULT="${MENU_IDS[$MENU_SELECTED]}"
                menu_show_cursor
                menu_exit_alt_screen
                trap - EXIT
                return 0
                ;;
            $'\x1b')  # Escape sequence
                read -rsn2 -t 1 key
                case "$key" in
                    '[A')  # Up
                        ((MENU_SELECTED--))
                        [ $MENU_SELECTED -lt 0 ] && MENU_SELECTED=$((total - 1))
                        menu_skip_separator "up"
                        ;;
                    '[B')  # Down
                        ((MENU_SELECTED++))
                        [ $MENU_SELECTED -ge $total ] && MENU_SELECTED=0
                        menu_skip_separator "down"
                        ;;
                esac

                # Only redraw if selection changed
                if [ $prev_selected -ne $MENU_SELECTED ]; then
                    menu_redraw_changed $prev_selected $MENU_SELECTED
                fi
                ;;
        esac
    done
}

# Convenience function for simple menus
# Usage: result=$(menu_select "Title" "id1:Label 1" "id2:Label 2" ...)
menu_select() {
    local title="$1"
    shift

    menu_init "$title"

    for item in "$@"; do
        if [ "$item" = "---" ]; then
            menu_add_separator
        else
            local id="${item%%:*}"
            local rest="${item#*:}"
            local label="${rest%%:*}"
            local desc=""
            if [[ "$rest" == *:* ]]; then
                desc="${rest#*:}"
            fi
            menu_add_item "$id" "$label" "$desc"
        fi
    done

    if menu_run; then
        echo "$MENU_RESULT"
        return 0
    else
        return 1
    fi
}
