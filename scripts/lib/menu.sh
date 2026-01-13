#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  MENU LIBRARY - Polished terminal menus inspired by opencode
#══════════════════════════════════════════════════════════════════════════════
#
#  Clean, minimal design with:
#  - Full-line background highlighting for selected items
#  - Inline descriptions in muted color
#  - No heavy box characters
#  - Consistent spacing
#
#  USAGE:
#    source ~/.claude-workspace/scripts/lib/menu.sh
#
#    menu_init "Title"
#    menu_add_item "item1" "Label 1" "Description 1"
#    menu_add_item "item2" "Label 2" "Description 2"
#    menu_add_separator "Section"
#    menu_add_item "quit" "Quit" "Exit the menu"
#
#    menu_run
#    echo "Selected: $MENU_RESULT"
#
#══════════════════════════════════════════════════════════════════════════════

# Theme colors (semantic, following opencode pattern)
# Using 256-color codes for better terminal compatibility
THEME_RESET='\033[0m'
THEME_BOLD='\033[1m'
THEME_DIM='\033[2m'

# Primary: orange/amber (opencode style)
THEME_PRIMARY='\033[38;5;216m'        # Light peach/orange
THEME_PRIMARY_BG='\033[48;5;216m'     # Background version
THEME_PRIMARY_FG_ON_BG='\033[38;5;234m'  # Dark text on primary bg

# Text colors
THEME_TEXT='\033[38;5;252m'           # Light gray text
THEME_TEXT_MUTED='\033[38;5;245m'     # Muted gray
THEME_TEXT_DIM='\033[38;5;240m'       # Dimmer gray

# UI colors
THEME_ACCENT='\033[38;5;183m'         # Purple accent
THEME_SUCCESS='\033[38;5;114m'        # Green
THEME_WARNING='\033[38;5;215m'        # Orange
THEME_ERROR='\033[38;5;203m'          # Red

# Background colors
THEME_BG_SELECTED='\033[48;5;238m'    # Subtle dark background for selected
THEME_BG_PANEL='\033[48;5;236m'       # Panel background

# State
MENU_TITLE=""
MENU_ITEMS=()
MENU_IDS=()
MENU_DESCRIPTIONS=()
MENU_TYPES=()      # "item" or "separator"
MENU_FOOTERS=()    # Optional footer text (right-aligned)
MENU_SELECTED=0
MENU_RESULT=""
MENU_HINT="esc"
MENU_SUBTITLE=""

# Terminal state
MENU_ROWS=0
MENU_COLS=0

# Layout constants
MENU_PADDING_LEFT=4
MENU_ITEM_START_ROW=4

# Initialize menu
menu_init() {
    MENU_TITLE="$1"
    MENU_SUBTITLE="${2:-}"
    MENU_ITEMS=()
    MENU_IDS=()
    MENU_DESCRIPTIONS=()
    MENU_TYPES=()
    MENU_FOOTERS=()
    MENU_SELECTED=0
    MENU_RESULT=""
    MENU_HINT="esc"

    # Get terminal size
    MENU_ROWS=$(tput lines)
    MENU_COLS=$(tput cols)
}

# Add a menu item
menu_add_item() {
    local id="$1"
    local label="$2"
    local description="${3:-}"
    local footer="${4:-}"

    MENU_IDS+=("$id")
    MENU_ITEMS+=("$label")
    MENU_DESCRIPTIONS+=("$description")
    MENU_TYPES+=("item")
    MENU_FOOTERS+=("$footer")
}

# Add a separator/section header
menu_add_separator() {
    local label="${1:-}"
    MENU_IDS+=("")
    MENU_ITEMS+=("$label")
    MENU_DESCRIPTIONS+=("")
    MENU_TYPES+=("separator")
    MENU_FOOTERS+=("")
}

# Set custom hint text (shown top-right)
menu_set_hint() {
    MENU_HINT="$1"
}

# === Terminal Control ===

menu_goto() {
    printf '\033[%d;%dH' "$1" "${2:-1}"
}

menu_clear_line() {
    printf '\033[K'
}

menu_clear_below() {
    printf '\033[J'
}

menu_hide_cursor() {
    printf '\033[?25l'
}

menu_show_cursor() {
    printf '\033[?25h'
}

menu_enter_alt_screen() {
    tput smcup 2>/dev/null || printf '\033[?1049h'
}

menu_exit_alt_screen() {
    tput rmcup 2>/dev/null || printf '\033[?1049l'
}

# === Drawing Functions ===

# Draw clean header: title on left, hint on right
menu_draw_header() {
    menu_goto 1 1
    menu_clear_line

    # Empty line for breathing room
    echo ""
    menu_clear_line

    # Title line with hint on right
    local title_padding=""
    for ((i=0; i<MENU_PADDING_LEFT; i++)); do
        title_padding+=" "
    done

    # Calculate spacing for right-aligned hint
    local title_len=${#MENU_TITLE}
    local hint_len=${#MENU_HINT}
    local available=$((MENU_COLS - MENU_PADDING_LEFT - title_len - hint_len - 4))
    local spacing=""
    for ((i=0; i<available; i++)); do
        spacing+=" "
    done

    echo -e "${title_padding}${THEME_TEXT}${THEME_BOLD}${MENU_TITLE}${THEME_RESET}${spacing}${THEME_TEXT_MUTED}${MENU_HINT}${THEME_RESET}"
    menu_clear_line

    # Subtitle or empty line
    if [ -n "$MENU_SUBTITLE" ]; then
        echo -e "${title_padding}${THEME_TEXT_MUTED}${MENU_SUBTITLE}${THEME_RESET}"
    else
        echo ""
    fi
    menu_clear_line
    echo ""
}

# Draw a single menu item
menu_draw_item() {
    local index=$1
    local row=$((MENU_ITEM_START_ROW + index))

    local id="${MENU_IDS[$index]}"
    local label="${MENU_ITEMS[$index]}"
    local desc="${MENU_DESCRIPTIONS[$index]}"
    local type="${MENU_TYPES[$index]}"
    local footer="${MENU_FOOTERS[$index]}"

    menu_goto $row 1
    menu_clear_line

    # Build padding
    local padding=""
    for ((i=0; i<MENU_PADDING_LEFT; i++)); do
        padding+=" "
    done

    if [ "$type" = "separator" ]; then
        # Section header - just the label in accent color with spacing
        if [ -n "$label" ]; then
            echo -e "${padding}${THEME_ACCENT}${THEME_BOLD}${label}${THEME_RESET}"
        else
            echo ""
        fi
        return
    fi

    # Calculate available width for content
    local content_width=$((MENU_COLS - MENU_PADDING_LEFT - 4))

    if [ $index -eq $MENU_SELECTED ]; then
        # Selected item - full line background
        # Build the line content
        local line_content="${label}"
        if [ -n "$desc" ]; then
            line_content="${label} ${THEME_TEXT_DIM}${desc}${THEME_RESET}${THEME_PRIMARY_BG}${THEME_PRIMARY_FG_ON_BG}"
        fi

        # Pad to full width for consistent background
        local visible_len=$((${#label} + ${#desc} + 1))
        local fill_spaces=$((content_width - visible_len))
        local fill=""
        for ((i=0; i<fill_spaces && i<200; i++)); do
            fill+=" "
        done

        echo -e "${padding}${THEME_PRIMARY_BG}${THEME_PRIMARY_FG_ON_BG}${THEME_BOLD} ${label}${THEME_RESET}${THEME_PRIMARY_BG}${THEME_PRIMARY_FG_ON_BG}${fill}${THEME_RESET}"
    else
        # Normal item - no background
        if [ -n "$desc" ]; then
            echo -e "${padding} ${THEME_TEXT}${label}${THEME_RESET} ${THEME_TEXT_MUTED}${desc}${THEME_RESET}"
        else
            echo -e "${padding} ${THEME_TEXT}${label}${THEME_RESET}"
        fi
    fi
}

# Draw all menu items
menu_draw_items() {
    local total=${#MENU_ITEMS[@]}
    for ((i=0; i<total; i++)); do
        menu_draw_item $i
    done

    # Clear remaining lines
    local end_row=$((MENU_ITEM_START_ROW + total))
    menu_goto $end_row 1
    menu_clear_below
}

# Redraw only changed items
menu_redraw_changed() {
    local prev=$1
    local curr=$2
    menu_draw_item $prev
    menu_draw_item $curr
}

# Skip separators when navigating
menu_skip_separator() {
    local direction=$1
    local total=${#MENU_ITEMS[@]}
    local iterations=0

    while [ "${MENU_TYPES[$MENU_SELECTED]}" = "separator" ]; do
        if [ "$direction" = "down" ]; then
            ((MENU_SELECTED++))
            [ $MENU_SELECTED -ge $total ] && MENU_SELECTED=0
        else
            ((MENU_SELECTED--))
            [ $MENU_SELECTED -lt 0 ] && MENU_SELECTED=$((total - 1))
        fi
        ((iterations++))
        [ $iterations -gt $total ] && break
    done
}

# === Main Menu Loop ===

menu_run() {
    local total=${#MENU_ITEMS[@]}

    if [ $total -eq 0 ]; then
        MENU_RESULT=""
        return 1
    fi

    menu_enter_alt_screen
    menu_hide_cursor
    trap 'menu_show_cursor; menu_exit_alt_screen' EXIT

    # Skip initial separators
    menu_skip_separator "down"

    # Initial draw
    menu_draw_header
    menu_draw_items

    while true; do
        read -rsn1 key
        local prev_selected=$MENU_SELECTED

        case "$key" in
            q|Q|$'\x1b')
                # Check if it's just escape or escape sequence
                if [ "$key" = $'\x1b' ]; then
                    read -rsn1 -t 0.1 next_key
                    if [ -z "$next_key" ]; then
                        # Just escape, quit
                        MENU_RESULT=""
                        menu_show_cursor
                        menu_exit_alt_screen
                        trap - EXIT
                        return 1
                    else
                        # Escape sequence, handle arrow keys
                        read -rsn1 -t 0.1 third_key
                        case "${next_key}${third_key}" in
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
                        if [ $prev_selected -ne $MENU_SELECTED ]; then
                            menu_redraw_changed $prev_selected $MENU_SELECTED
                        fi
                    fi
                else
                    # q/Q pressed
                    MENU_RESULT=""
                    menu_show_cursor
                    menu_exit_alt_screen
                    trap - EXIT
                    return 1
                fi
                ;;
            "")  # Enter
                MENU_RESULT="${MENU_IDS[$MENU_SELECTED]}"
                menu_show_cursor
                menu_exit_alt_screen
                trap - EXIT
                return 0
                ;;
        esac
    done
}

# === Convenience Functions ===

# Simple menu selection
# Usage: result=$(menu_select "Title" "id1:Label 1:desc" "id2:Label 2" ...)
menu_select() {
    local title="$1"
    shift

    menu_init "$title"

    for item in "$@"; do
        if [ "$item" = "---" ] || [[ "$item" == "---:"* ]]; then
            local sep_label="${item#---:}"
            menu_add_separator "$sep_label"
        else
            local id="${item%%:*}"
            local rest="${item#*:}"
            local label="${rest%%:*}"
            local desc=""
            if [[ "$rest" == *:* ]] && [ "$rest" != "$label" ]; then
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
