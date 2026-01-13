#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE SETTINGS
#══════════════════════════════════════════════════════════════════════════════
#
#  Configure external AI tools and delegation strategy.
#
#  USAGE:
#    settings.sh              Interactive settings menu
#    settings.sh --show       Show current settings
#    settings.sh --reset      Reset to defaults
#
#══════════════════════════════════════════════════════════════════════════════

INSTALL_DIR="$HOME/.claude-workspace"
SETTINGS_FILE="$INSTALL_DIR/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# Source the menu library for flicker-free menus
source "$INSTALL_DIR/scripts/lib/menu.sh"

# Colors (also defined in menu.sh but kept for backward compatibility)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Cursor positioning functions
goto_row() {
    printf '\033[%d;1H' "$1"
}

clear_line() {
    printf '\033[K'
}

clear_below() {
    printf '\033[J'
}

hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

enter_alt_screen() {
    tput smcup 2>/dev/null || printf '\033[?1049h'
}

exit_alt_screen() {
    tput rmcup 2>/dev/null || printf '\033[?1049l'
}

# Default settings
DEFAULT_SETTINGS='{
  "delegation": {
    "level": 2,
    "levels": {
      "0": {"name": "Disabled", "description": "No delegation - Claude handles everything"},
      "1": {"name": "Minimal", "description": "Only delegate simple research and summarization"},
      "2": {"name": "Moderate", "description": "Delegate routine tasks like tests, types, docs"},
      "3": {"name": "Aggressive", "description": "Delegate most implementation, Claude reviews"},
      "4": {"name": "Orchestrator", "description": "Claude only orchestrates, delegates almost everything"}
    },
    "visible_by_default": false,
    "use_branches": true
  },
  "ai_tools": {
    "gemini": {"enabled": false, "command": "gemini", "name": "Gemini CLI", "installed": false},
    "opencode": {"enabled": false, "command": "opencode", "name": "OpenCode", "installed": false},
    "codex": {"enabled": false, "command": "codex", "name": "OpenAI Codex", "installed": false},
    "aider": {"enabled": false, "command": "aider", "name": "Aider", "installed": false},
    "continue": {"enabled": false, "command": "continue", "name": "Continue", "installed": false}
  }
}'

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Initialize settings if not exists
init_settings() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$(dirname "$CLAUDE_MD")"

    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "$DEFAULT_SETTINGS" | jq '.' > "$SETTINGS_FILE"
    fi

    # Detect installed tools
    detect_installed_tools
}

# Detect which AI tools are installed
detect_installed_tools() {
    local tools=("gemini" "opencode" "codex" "aider" "continue")
    local temp=$(mktemp)

    cp "$SETTINGS_FILE" "$temp"

    for tool in "${tools[@]}"; do
        local cmd=$(jq -r ".ai_tools.$tool.command" "$SETTINGS_FILE")
        if command -v "$cmd" &> /dev/null; then
            jq ".ai_tools.$tool.installed = true" "$temp" > "${temp}.new" && mv "${temp}.new" "$temp"
        else
            jq ".ai_tools.$tool.installed = false" "$temp" > "${temp}.new" && mv "${temp}.new" "$temp"
        fi
    done

    mv "$temp" "$SETTINGS_FILE"
}

# Get current delegation level
get_delegation_level() {
    jq -r '.delegation.level' "$SETTINGS_FILE"
}

# Get delegation level name
get_delegation_name() {
    local level=$(get_delegation_level)
    jq -r ".delegation.levels[\"$level\"].name" "$SETTINGS_FILE"
}

# Show header - draws at current position or row 1
show_header() {
    local start_row=${1:-1}
    goto_row $start_row
    clear_line
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    clear_line
    echo -e "${CYAN}║${NC}  ${GREEN}CLAUDE WORKSPACE SETTINGS${NC}                                                  ${CYAN}║${NC}"
    clear_line
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    clear_line
    echo ""
}

# Draw header once (for alt screen)
draw_header_once() {
    goto_row 1
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}CLAUDE WORKSPACE SETTINGS${NC}                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Interactive slider for delegation level
delegation_slider() {
    local current=$(get_delegation_level)
    local max=4
    local SLIDER_ROW=8   # Row where slider is drawn
    local LEVELS_ROW=15  # Row where levels list starts

    # Pre-load level data to avoid jq calls during draw
    local names=() descs=()
    for ((i=0; i<=max; i++)); do
        names[$i]=$(jq -r ".delegation.levels[\"$i\"].name" "$SETTINGS_FILE")
        descs[$i]=$(jq -r ".delegation.levels[\"$i\"].description" "$SETTINGS_FILE")
    done

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static elements once
    draw_static() {
        draw_header_once
        goto_row 5
        echo -e "${BOLD}Delegation Strategy${NC}"
        echo -e "${DIM}How much should Claude delegate to external AI tools?${NC}"
        echo ""
    }

    # Draw just the slider bar
    draw_slider_bar() {
        goto_row $SLIDER_ROW
        clear_line
        echo -n "  "
        for ((i=0; i<=max; i++)); do
            if [ $i -eq $current ]; then
                echo -ne "${GREEN}●${NC}"
            else
                echo -ne "${DIM}○${NC}"
            fi
            [ $i -lt $max ] && echo -n "───"
        done
        echo ""

        goto_row $((SLIDER_ROW + 1))
        clear_line
        echo -e "  ${DIM}Off${NC}                           ${DIM}Max${NC}"

        goto_row $((SLIDER_ROW + 3))
        clear_line
        echo -e "  ${BOLD}Level $current: ${names[$current]}${NC}"
        goto_row $((SLIDER_ROW + 4))
        clear_line
        echo -e "  ${DIM}${descs[$current]}${NC}"
    }

    # Draw levels list
    draw_levels() {
        goto_row $LEVELS_ROW
        clear_line
        echo -e "${BLUE}Levels:${NC}"
        for ((i=0; i<=max; i++)); do
            goto_row $((LEVELS_ROW + 1 + i * 2))
            clear_line
            if [ $i -eq $current ]; then
                echo -e "  ${GREEN}▶ [$i] ${names[$i]}${NC}"
            else
                echo -e "  ${DIM}  [$i] ${names[$i]}${NC}"
            fi
            goto_row $((LEVELS_ROW + 2 + i * 2))
            clear_line
            if [ $i -eq $current ]; then
                echo -e "    ${DIM}${descs[$i]}${NC}"
            fi
        done

        goto_row $((LEVELS_ROW + 12))
        clear_line
        echo -e "  ${DIM}←/→: Adjust   Enter: Confirm   q: Cancel${NC}"
    }

    # Initial draw
    draw_static
    draw_slider_bar
    draw_levels

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            "")  # Enter
                # Save setting
                local temp=$(mktemp)
                jq ".delegation.level = $current" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 0
                ;;
            $'\x1b')
                read -rsn2 -t 1 key
                case "$key" in
                    '[D')  # Left
                        ((current--))
                        [ $current -lt 0 ] && current=0
                        draw_slider_bar
                        draw_levels
                        ;;
                    '[C')  # Right
                        ((current++))
                        [ $current -gt $max ] && current=$max
                        draw_slider_bar
                        draw_levels
                        ;;
                esac
                ;;
            [0-4])  # Direct number input
                current=$key
                draw_slider_bar
                draw_levels
                ;;
        esac
    done
}

# Configure AI tools
configure_ai_tools() {
    # Get list of tools
    local tools=($(jq -r '.ai_tools | keys[]' "$SETTINGS_FILE"))
    local total=${#tools[@]}
    local current=0
    local ITEMS_ROW=9  # Row where items start

    # Pre-load tool data
    local tool_names=() tool_cmds=() tool_enabled=() tool_installed=()
    reload_tool_data() {
        for ((i=0; i<total; i++)); do
            local tool="${tools[$i]}"
            tool_names[$i]=$(jq -r ".ai_tools.$tool.name" "$SETTINGS_FILE")
            tool_cmds[$i]=$(jq -r ".ai_tools.$tool.command" "$SETTINGS_FILE")
            tool_enabled[$i]=$(jq -r ".ai_tools.$tool.enabled" "$SETTINGS_FILE")
            tool_installed[$i]=$(jq -r ".ai_tools.$tool.installed" "$SETTINGS_FILE")
        done
    }
    reload_tool_data

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header
    draw_static() {
        draw_header_once
        goto_row 5
        echo -e "${BOLD}External AI Tools${NC}"
        echo -e "${DIM}Configure which AI tools Claude can delegate to${NC}"
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Space: Toggle   Enter: Done   a: Auto-detect${NC}"
    }

    # Draw a single tool item
    draw_tool_item() {
        local i=$1
        local row=$((ITEMS_ROW + i * 2))

        local checkbox="[ ]"
        local status=""

        if [ "${tool_enabled[$i]}" = "true" ]; then
            checkbox="${GREEN}[✓]${NC}"
        fi

        if [ "${tool_installed[$i]}" = "true" ]; then
            status="${GREEN}(installed)${NC}"
        else
            status="${YELLOW}(not found)${NC}"
        fi

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e "  ${BOLD}▶ $checkbox ${tool_names[$i]}${NC} $status"
            goto_row $((row + 1))
            clear_line
            echo -e "    ${DIM}Command: ${tool_cmds[$i]}${NC}"
        else
            echo -e "    $checkbox ${tool_names[$i]} $status"
            goto_row $((row + 1))
            clear_line
        fi
    }

    # Draw all tools
    draw_all_tools() {
        for ((i=0; i<total; i++)); do
            draw_tool_item $i
        done
    }

    # Draw footer with count
    draw_footer() {
        local enabled_count=0
        for ((i=0; i<total; i++)); do
            [ "${tool_enabled[$i]}" = "true" ] && ((enabled_count++))
        done
        goto_row $((ITEMS_ROW + total * 2 + 1))
        clear_line
        echo -e "  ${BLUE}Enabled: $enabled_count / $total${NC}"
    }

    # Initial draw
    draw_static
    draw_all_tools
    draw_footer

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            "")  # Enter
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 0
                ;;
            a|A)  # Auto-detect
                detect_installed_tools
                # Enable all installed tools
                for tool in "${tools[@]}"; do
                    local installed=$(jq -r ".ai_tools.$tool.installed" "$SETTINGS_FILE")
                    if [ "$installed" = "true" ]; then
                        local temp=$(mktemp)
                        jq ".ai_tools.$tool.enabled = true" "$SETTINGS_FILE" > "$temp"
                        mv "$temp" "$SETTINGS_FILE"
                    fi
                done
                reload_tool_data
                draw_all_tools
                draw_footer
                ;;
            " ")  # Space - toggle
                local tool="${tools[$current]}"
                local new_val="true"
                [ "${tool_enabled[$current]}" = "true" ] && new_val="false"

                local temp=$(mktemp)
                jq ".ai_tools.$tool.enabled = $new_val" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                tool_enabled[$current]=$new_val
                draw_tool_item $current
                draw_footer
                ;;
            $'\x1b')
                read -rsn2 -t 1 key
                local prev=$current
                case "$key" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        ;;
                esac
                if [ $prev -ne $current ]; then
                    draw_tool_item $prev
                    draw_tool_item $current
                fi
                ;;
        esac
    done
}

# Add custom AI tool
add_custom_tool() {
    show_header
    echo -e "${BOLD}Add Custom AI Tool${NC}"
    echo ""

    read -p "Tool ID (e.g., 'mytool'): " tool_id
    [ -z "$tool_id" ] && return 1

    read -p "Display name (e.g., 'My AI Tool'): " tool_name
    tool_name=${tool_name:-$tool_id}

    read -p "Command (e.g., 'mytool'): " tool_cmd
    tool_cmd=${tool_cmd:-$tool_id}

    # Check if installed
    local installed="false"
    if command -v "$tool_cmd" &> /dev/null; then
        installed="true"
        echo -e "${GREEN}✓${NC} Found: $tool_cmd"
    else
        echo -e "${YELLOW}!${NC} Command not found: $tool_cmd"
    fi

    # Add to settings
    local temp=$(mktemp)
    jq ".ai_tools.$tool_id = {\"enabled\": true, \"command\": \"$tool_cmd\", \"name\": \"$tool_name\", \"installed\": $installed}" "$SETTINGS_FILE" > "$temp"
    mv "$temp" "$SETTINGS_FILE"

    echo ""
    echo -e "${GREEN}✓${NC} Added '$tool_name'"
    read -p "Press Enter to continue..."
}

# Configure delegation behavior
configure_delegation_options() {
    local current=0
    local total=2
    local OPTION_ROWS=(9 25)  # Row numbers for each option box

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Get current values
    get_values() {
        visible=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
        branches=$(jq -r '.delegation.use_branches // true' "$SETTINGS_FILE")
    }

    # Draw static header
    draw_static() {
        goto_row 1
        draw_header_once
        goto_row 5
        echo -e "${BOLD}Delegation Behavior${NC}"
        echo -e "${DIM}Configure how Claude delegates tasks to other AI tools${NC}"
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Space: Toggle   Enter/q: Done${NC}"
    }

    # Draw option box
    draw_option() {
        local idx=$1
        local row=${OPTION_ROWS[$idx]}
        local is_selected=$((idx == current))

        get_values

        goto_row $row

        if [ $idx -eq 0 ]; then
            # Visible Delegation
            local status="${RED}Off${NC}"
            [ "$visible" = "true" ] && status="${GREEN}On${NC}"

            local border_color="${CYAN}"
            local indicator="  "
            if [ $is_selected -eq 1 ]; then
                border_color="${GREEN}"
                indicator="${GREEN}▶${NC} "
            fi

            clear_line
            echo -e "${indicator}${border_color}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC} ${BOLD}Visible Delegation${NC}                                            [$status]"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     When enabled, delegated tasks open in a Ghostty split pane so you"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     can watch the AI work in real-time. Useful for:"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Debugging delegation issues"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Learning how other AIs approach problems"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Monitoring progress on complex tasks"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${DIM}Layout: Claude on left, delegated AI on right${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${DIM}Override per-task: delegate.sh ... --visible${NC}"
            clear_line
            echo -e "${indicator}${border_color}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
        else
            # Branch Isolation
            local status="${RED}Off${NC}"
            [ "$branches" = "true" ] && status="${GREEN}On${NC}"

            local border_color="${CYAN}"
            local indicator="  "
            if [ $is_selected -eq 1 ]; then
                border_color="${GREEN}"
                indicator="${GREEN}▶${NC} "
            fi

            clear_line
            echo -e "${indicator}${border_color}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC} ${BOLD}Branch Isolation${NC}                                              [$status]"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     When enabled, each delegated task runs on its own git branch."
            clear_line
            echo -e "${indicator}${border_color}│${NC}     This prevents multiple AI agents from conflicting. Benefits:"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} No conflicts when running parallel delegations"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Easy to review changes before merging"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Safe to discard failed attempts"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${GREEN}✓${NC} Clear git history of who did what"
            clear_line
            echo -e "${indicator}${border_color}│${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${DIM}Branch format: delegate/<ai>/<task-summary>-<timestamp>${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${DIM}Example: delegate/gemini/write-unit-tests-20250113_143022${NC}"
            clear_line
            echo -e "${indicator}${border_color}│${NC}     ${DIM}Override per-task: delegate.sh ... --branch or --no-branch${NC}"
            clear_line
            echo -e "${indicator}${border_color}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
        fi
    }

    # Initial draw
    draw_static
    draw_option 0
    draw_option 1

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q|"")  # q or Enter - go back
                show_cursor
                exit_alt_screen
                trap - EXIT
                return
                ;;
            " ")  # Space - toggle current option
                if [ $current -eq 0 ]; then
                    local new_val="true"
                    [ "$visible" = "true" ] && new_val="false"
                    local temp=$(mktemp)
                    jq ".delegation.visible_by_default = $new_val" "$SETTINGS_FILE" > "$temp"
                    mv "$temp" "$SETTINGS_FILE"
                else
                    local new_val="true"
                    [ "$branches" = "true" ] && new_val="false"
                    local temp=$(mktemp)
                    jq ".delegation.use_branches = $new_val" "$SETTINGS_FILE" > "$temp"
                    mv "$temp" "$SETTINGS_FILE"
                fi
                draw_option $current
                ;;
            $'\x1b')  # Escape sequence
                read -rsn2 -t 1 seq
                local prev=$current
                case "$seq" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        ;;
                esac
                if [ $prev -ne $current ]; then
                    draw_option $prev
                    draw_option $current
                fi
                ;;
        esac
    done
}

# Generate CLAUDE.md based on settings
generate_claude_md() {
    local level=$(get_delegation_level)
    local level_name=$(get_delegation_name)

    # Get enabled tools
    local enabled_tools=$(jq -r '[.ai_tools | to_entries[] | select(.value.enabled == true) | .key] | join(" ")' "$SETTINGS_FILE")

    if [ -z "$enabled_tools" ] || [ "$level" -eq 0 ]; then
        # No delegation
        cat > "$CLAUDE_MD" << 'EOF'
# Claude Workspace

AI delegation is currently disabled. Claude handles all tasks directly.

To enable delegation, run: `claude-workspace settings`
EOF
        return
    fi

    # Build tool list for instructions
    local tool_list=""
    local tool_examples=""

    for tool in $enabled_tools; do
        local name=$(jq -r ".ai_tools.$tool.name" "$SETTINGS_FILE")
        tool_list="$tool_list- \`$tool\`: $name\n"
        tool_examples="$tool_examples# Delegate to $tool\n~/.claude-workspace/scripts/delegate.sh $tool \"task description\" /path/to/project\n\n"
    done

    # Generate based on level
    cat > "$CLAUDE_MD" << EOF
# AI Delegation Instructions

You have access to a multi-AI delegation system. Use it to delegate tasks to other AI models while you focus on complex work.

**Current Strategy: ${level_name} (Level ${level}/4)**

## Available AI Tools

$(echo -e "$tool_list")

## Delegation Script

\`\`\`bash
~/.claude-workspace/scripts/delegate.sh <ai_name> <task_description> <project_path>
\`\`\`

EOF

    # Add level-specific instructions
    case $level in
        1)  # Minimal
            cat >> "$CLAUDE_MD" << 'EOF'
## Delegation Strategy: Minimal

Only delegate simple, well-defined tasks:

**Delegate:**
- Research and summarization of large files
- Simple documentation lookups
- Gathering information from codebases

**Keep for yourself (Claude):**
- All code writing and modifications
- Architecture decisions
- Bug fixes and debugging
- Code review
- Any task requiring judgment

EOF
            ;;
        2)  # Moderate
            cat >> "$CLAUDE_MD" << 'EOF'
## Delegation Strategy: Moderate

Delegate routine implementation tasks:

**Delegate:**
- Research and summarization
- Type/interface generation from schemas
- Unit tests for pure functions
- Simple utility functions
- Documentation and JSDoc comments
- Boilerplate components
- CRUD operations

**Keep for yourself (Claude):**
- Architecture decisions and system design
- Complex business logic
- Debugging and troubleshooting
- Security-sensitive code
- Code review and integration
- Cross-cutting concerns

EOF
            ;;
        3)  # Aggressive
            cat >> "$CLAUDE_MD" << 'EOF'
## Delegation Strategy: Aggressive

Delegate most implementation, focus on review and architecture:

**Delegate:**
- Most feature implementation
- Component development
- API endpoint creation
- Database queries and migrations
- Test writing (unit, integration)
- Documentation
- Refactoring tasks
- Bug fixes with clear reproduction steps

**Keep for yourself (Claude):**
- Architecture decisions
- Security review
- Performance optimization strategy
- Final code review and approval
- Complex algorithmic problems
- Integration of delegated work

EOF
            ;;
        4)  # Orchestrator
            cat >> "$CLAUDE_MD" << 'EOF'
## Delegation Strategy: Orchestrator

Claude acts as architect and reviewer, delegating almost everything:

**Delegate:**
- All feature implementation
- All component development
- All tests and documentation
- Bug fixes
- Refactoring
- Code organization
- API development
- Database work

**Keep for yourself (Claude):**
- High-level architecture planning
- Task breakdown and delegation
- Code review of delegated work
- Integration decisions
- Security audit
- Performance review
- Final approval

**Workflow:**
1. Break down user requests into delegatable tasks
2. Assign tasks to appropriate AI tools
3. Review completed work
4. Integrate and verify
5. Handle any issues that arise

EOF
            ;;
    esac

    # Add common sections
    cat >> "$CLAUDE_MD" << 'EOF'
## Async Delegation (Recommended)

Use async delegation to continue working while other AIs handle tasks:

```bash
# Check CLI auth status first
~/.claude-workspace/scripts/check-auth.sh <ai_name>

# Delegate async
~/.claude-workspace/scripts/delegate-async.sh <ai_name> <task_description> <project_path>

# Check status
~/.claude-workspace/scripts/check-status.sh <task_id>
```

## Quality Checklist

After receiving delegated work, verify:
- Code compiles without errors
- Follows project conventions
- No security issues
- Tests pass
- No over-engineering

---
*Generated by Claude Workspace. Run `claude-workspace settings` to adjust.*
EOF

    echo -e "${GREEN}✓${NC} Updated $CLAUDE_MD"
}

# Show current settings
show_settings() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Current Settings${NC}                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local level=$(get_delegation_level)
    local level_name=$(get_delegation_name)
    local level_desc=$(jq -r ".delegation.levels[\"$level\"].description" "$SETTINGS_FILE")

    echo -e "${BOLD}Delegation Strategy:${NC}"
    echo -e "  Level: $level/4 ($level_name)"
    echo -e "  ${DIM}$level_desc${NC}"
    echo ""

    echo -e "${BOLD}Delegation Behavior:${NC}"
    local visible=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
    local branches=$(jq -r '.delegation.use_branches // true' "$SETTINGS_FILE")

    local visible_status="${RED}Off${NC}"
    local branches_status="${RED}Off${NC}"
    [ "$visible" = "true" ] && visible_status="${GREEN}On${NC}"
    [ "$branches" = "true" ] && branches_status="${GREEN}On${NC}"

    echo -e "  Visible delegation: $visible_status"
    echo -e "  Branch isolation: $branches_status"
    echo ""

    echo -e "${BOLD}AI Tools:${NC}"
    local tools=$(jq -r '.ai_tools | to_entries[] | "\(.key):\(.value.enabled):\(.value.installed):\(.value.name)"' "$SETTINGS_FILE")

    while IFS=: read -r id enabled installed name; do
        local status_icon="${RED}✗${NC}"
        [ "$enabled" = "true" ] && status_icon="${GREEN}✓${NC}"

        local install_status=""
        [ "$installed" = "true" ] && install_status="${GREEN}(installed)${NC}" || install_status="${YELLOW}(not found)${NC}"

        echo -e "  $status_icon $name $install_status"
    done <<< "$tools"

    echo ""
}

# Main settings menu
main_menu() {
    # Menu items: id, label, description
    local -a menu_ids=("delegation" "tools" "custom" "behavior" "apply" "show" "reset" "done")
    local -a menu_labels=(
        "Adjust delegation level"
        "Configure AI tools"
        "Add custom AI tool"
        "Delegation behavior"
        "Apply settings"
        "Show current settings"
        "Reset to defaults"
        "Done & Save"
    )
    local -a menu_descs=(
        "Set how much Claude delegates to other AI tools"
        "Enable/disable specific AI tools for delegation"
        "Add a custom AI tool command"
        "Configure visibility and branch isolation"
        "Update CLAUDE.md with current settings"
        "Display all current configuration"
        "Reset all settings to defaults"
        "Save settings and exit"
    )
    local total=${#menu_ids[@]}
    local current=0
    local ITEMS_ROW=10

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header with current config
    draw_header() {
        local level=$(get_delegation_level)
        local level_name=$(get_delegation_name)
        local enabled_count=$(jq '[.ai_tools[] | select(.enabled == true)] | length' "$SETTINGS_FILE")

        goto_row 1
        draw_header_once
        goto_row 5
        clear_line
        echo -e "${BOLD}Current Configuration:${NC}"
        clear_line
        echo -e "  Delegation: Level $level ($level_name)"
        clear_line
        echo -e "  AI Tools: $enabled_count enabled"
        clear_line
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Enter: Select   q: Done${NC}"
    }

    # Draw a single menu item
    draw_item() {
        local i=$1
        local row=$((ITEMS_ROW + i))

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e " ${GREEN}▶${NC} ${BOLD}${menu_labels[$i]}${NC}"
        else
            echo -e "   ${menu_labels[$i]}"
        fi
    }

    # Draw all items
    draw_all_items() {
        for ((i=0; i<total; i++)); do
            draw_item $i
        done
    }

    # Draw description for current item
    draw_description() {
        goto_row $((ITEMS_ROW + total + 1))
        clear_line
        echo ""
        clear_line
        echo -e "  ${DIM}${menu_descs[$current]}${NC}"
    }

    # Initial draw
    draw_header
    draw_all_items
    draw_description

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                # Save and exit
                goto_row $((ITEMS_ROW + total + 4))
                clear_below
                generate_claude_md
                echo ""
                echo -e "${GREEN}Settings saved!${NC}"
                show_cursor
                exit_alt_screen
                trap - EXIT
                exit 0
                ;;
            "")  # Enter - select current item
                local selected_id="${menu_ids[$current]}"
                case "$selected_id" in
                    delegation)
                        delegation_slider
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    tools)
                        configure_ai_tools
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    custom)
                        show_cursor
                        exit_alt_screen
                        add_custom_tool
                        enter_alt_screen
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    behavior)
                        configure_delegation_options
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    apply)
                        goto_row $((ITEMS_ROW + total + 4))
                        clear_below
                        generate_claude_md
                        sleep 1
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    show)
                        show_cursor
                        exit_alt_screen
                        show_settings
                        read -p "Press Enter to continue..."
                        enter_alt_screen
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    reset)
                        show_cursor
                        goto_row $((ITEMS_ROW + total + 4))
                        clear_below
                        read -p "Reset all settings to defaults? [y/N] " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            echo "$DEFAULT_SETTINGS" | jq '.' > "$SETTINGS_FILE"
                            detect_installed_tools
                            echo -e "${GREEN}✓${NC} Settings reset"
                            sleep 1
                        fi
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    done)
                        # Save and exit
                        goto_row $((ITEMS_ROW + total + 4))
                        clear_below
                        generate_claude_md
                        echo ""
                        echo -e "${GREEN}Settings saved!${NC}"
                        show_cursor
                        exit_alt_screen
                        trap - EXIT
                        exit 0
                        ;;
                esac
                ;;
            $'\x1b')  # Escape sequence
                read -rsn2 -t 1 seq
                local prev=$current
                case "$seq" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        ;;
                esac
                if [ $prev -ne $current ]; then
                    draw_item $prev
                    draw_item $current
                    draw_description
                fi
                ;;
        esac
    done
}

# Handle arguments
init_settings

case "$1" in
    --show|-s)
        show_settings
        ;;
    --reset)
        echo "$DEFAULT_SETTINGS" | jq '.' > "$SETTINGS_FILE"
        detect_installed_tools
        echo -e "${GREEN}✓${NC} Settings reset to defaults"
        ;;
    --apply)
        generate_claude_md
        ;;
    --help|-h)
        echo "Claude Workspace Settings"
        echo ""
        echo "Usage:"
        echo "  settings.sh              Interactive settings menu"
        echo "  settings.sh --show       Show current settings"
        echo "  settings.sh --reset      Reset to defaults"
        echo "  settings.sh --apply      Apply settings (update CLAUDE.md)"
        ;;
    *)
        main_menu
        ;;
esac
