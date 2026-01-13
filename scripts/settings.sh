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

# Theme colors (matching menu.sh polished theme)
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Semantic colors
PRIMARY='\033[38;5;216m'          # Light peach/orange
PRIMARY_BG='\033[48;5;216m'
PRIMARY_FG='\033[38;5;234m'       # Dark text on primary bg

TEXT='\033[38;5;252m'             # Light gray
TEXT_MUTED='\033[38;5;245m'       # Muted gray
TEXT_DIM='\033[38;5;240m'         # Dimmer gray

ACCENT='\033[38;5;183m'           # Purple accent
SUCCESS='\033[38;5;114m'          # Green
WARNING='\033[38;5;215m'          # Orange
ERROR='\033[38;5;203m'            # Red

# Legacy aliases
RED="$ERROR"
GREEN="$SUCCESS"
YELLOW="$WARNING"
BLUE="$ACCENT"
CYAN="$PRIMARY"

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

# Show header - clean polished style
show_header() {
    local start_row=${1:-1}
    goto_row $start_row
    clear_line
    echo ""
    clear_line
    echo -e "    ${TEXT}${BOLD}Settings${NC}"
    clear_line
    echo ""
}

# Draw header once (for alt screen)
draw_header_once() {
    goto_row 1
    echo ""
    echo -e "    ${TEXT}${BOLD}Settings${NC}"
    echo ""
}

# Interactive slider for delegation level
delegation_slider() {
    local current=$(get_delegation_level)
    local max=4
    local LEVELS_ROW=7  # Row where levels list starts

    # Pre-load level data to avoid jq calls during draw
    local names=() descs=()
    for ((i=0; i<=max; i++)); do
        names[$i]=$(jq -r ".delegation.levels[\"$i\"].name" "$SETTINGS_FILE")
        descs[$i]=$(jq -r ".delegation.levels[\"$i\"].description" "$SETTINGS_FILE")
    done

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header
    draw_static() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}Delegation Level${NC}                                                       ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}How much should Claude delegate to external AI tools?${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Levels${NC}"
    }

    # Draw a single level option
    draw_level() {
        local i=$1
        local row=$((LEVELS_ROW + i))

        goto_row $row
        clear_line

        if [ $i -eq $current ]; then
            echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} ${names[$i]} ${NC}${PRIMARY_BG}${PRIMARY_FG} ${descs[$i]} ${NC}"
        else
            echo -e "     ${TEXT}${names[$i]}${NC} ${TEXT_MUTED}${descs[$i]}${NC}"
        fi
    }

    # Draw all levels
    draw_all_levels() {
        for ((i=0; i<=max; i++)); do
            draw_level $i
        done
    }

    # Initial draw
    draw_static
    draw_all_levels

    while true; do
        IFS= read -rsn1 key
        local prev=$current

        case "$key" in
            q|Q)
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            $'\x1b')
                read -rsn2 -t 1 seq
                if [ -z "$seq" ]; then
                    # Just escape
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    return 1
                fi
                case "$seq" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$max
                        if [ $prev -ne $current ]; then
                            draw_level $prev
                            draw_level $current
                        fi
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -gt $max ] && current=0
                        if [ $prev -ne $current ]; then
                            draw_level $prev
                            draw_level $current
                        fi
                        ;;
                esac
                ;;
            "")  # Enter
                local temp=$(mktemp)
                jq ".delegation.level = $current" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 0
                ;;
            [0-4])  # Direct number input
                current=$key
                if [ $prev -ne $current ]; then
                    draw_level $prev
                    draw_level $current
                fi
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
    local ITEMS_ROW=7  # Row where items start

    # Pre-load tool data
    local tool_names=() tool_cmds=() tool_enabled=() tool_installed=()
    
    # Load initial state
    for ((i=0; i<total; i++)); do
        local tool="${tools[$i]}"
        tool_names[$i]=$(jq -r ".ai_tools.$tool.name" "$SETTINGS_FILE")
        tool_cmds[$i]=$(jq -r ".ai_tools.$tool.command" "$SETTINGS_FILE")
        tool_enabled[$i]=$(jq -r ".ai_tools.$tool.enabled" "$SETTINGS_FILE")
        tool_installed[$i]=$(jq -r ".ai_tools.$tool.installed" "$SETTINGS_FILE")
    done

    # Save changes to disk
    save_changes() {
        local temp=$(mktemp)
        cp "$SETTINGS_FILE" "$temp"
        for ((i=0; i<total; i++)); do
            local tool="${tools[$i]}"
            local enabled="${tool_enabled[$i]}"
            jq ".ai_tools.$tool.enabled = $enabled" "$temp" > "${temp}.new" && mv "${temp}.new" "$temp"
        done
        mv "$temp" "$SETTINGS_FILE"
    }

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header
    draw_static() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}AI Tools${NC}                                                               ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Configure which AI tools Claude can delegate to${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Available Tools${NC}  ${TEXT_DIM}space to toggle${NC}"
    }

    # Draw a single tool item
    draw_tool_item() {
        local i=$1
        local row=$((ITEMS_ROW + i))

        local checkbox="○"
        local status=""

        if [ "${tool_enabled[$i]}" = "true" ]; then
            checkbox="${SUCCESS}●${NC}"
        fi

        if [ "${tool_installed[$i]}" = "true" ]; then
            status="installed"
        else
            status="not found"
        fi

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} $checkbox ${tool_names[$i]} ${NC}${PRIMARY_BG}${PRIMARY_FG} ${status} ${NC}"
        else
            echo -e "     $checkbox ${TEXT}${tool_names[$i]}${NC} ${TEXT_MUTED}${status}${NC}"
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
        goto_row $((ITEMS_ROW + total + 2))
        clear_line
        echo -e "    ${TEXT_MUTED}$enabled_count of $total enabled${NC}"
    }

    # Initial draw
    draw_static
    draw_all_tools
    draw_footer

    while true; do
        IFS= read -rsn1 key

        case "$key" in
            q|Q)
                save_changes
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            "")  # Enter
                save_changes
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 0
                ;;
            a|A)  # Auto-detect
                detect_installed_tools
                # Reload data
                for ((i=0; i<total; i++)); do
                    local tool="${tools[$i]}"
                    local installed=$(jq -r ".ai_tools.$tool.installed" "$SETTINGS_FILE")
                    tool_installed[$i]=$installed
                    if [ "$installed" = "true" ]; then
                        tool_enabled[$i]="true"
                    fi
                done
                draw_all_tools
                draw_footer
                ;;
            " ")  # Space - toggle
                if [ "${tool_enabled[$current]}" = "true" ]; then
                    tool_enabled[$current]="false"
                else
                    tool_enabled[$current]="true"
                fi
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

# Configure delegation behavior - clean polished style
configure_delegation_options() {
    local current=0
    local total=2
    local ITEMS_ROW=7

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Get current values
    get_values() {
        visible=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
        branches=$(jq -r '.delegation.use_branches // true' "$SETTINGS_FILE")
    }
    get_values

    # Option data
    local -a opt_names=("Visible Delegation" "Branch Isolation")
    local -a opt_descs=(
        "Open delegated tasks in split pane"
        "Run each task on its own git branch"
    )

    # Draw static header
    draw_static() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}Delegation Behavior${NC}                                                    ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Configure how Claude delegates tasks to other AI tools${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Options${NC}  ${TEXT_DIM}space to toggle${NC}"
    }

    # Draw a single option
    draw_option() {
        local i=$1
        local row=$((ITEMS_ROW + i))
        get_values

        local checkbox="○"
        if [ $i -eq 0 ]; then
            [ "$visible" = "true" ] && checkbox="${SUCCESS}●${NC}"
        else
            [ "$branches" = "true" ] && checkbox="${SUCCESS}●${NC}"
        fi

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} $checkbox ${opt_names[$i]} ${NC}${PRIMARY_BG}${PRIMARY_FG} ${opt_descs[$i]} ${NC}"
        else
            echo -e "     $checkbox ${TEXT}${opt_names[$i]}${NC} ${TEXT_MUTED}${opt_descs[$i]}${NC}"
        fi
    }

    # Draw all options
    draw_all_options() {
        for ((i=0; i<total; i++)); do
            draw_option $i
        done
    }

    # Initial draw
    draw_static
    draw_all_options

    while true; do
        IFS= read -rsn1 key

        case "$key" in
            q|Q)
                show_cursor
                exit_alt_screen
                trap - EXIT
                return
                ;;
            "")  # Enter - go back
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
                if [ -z "$seq" ]; then
                    # Just escape
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    return
                fi
                local prev=$current
                case "$seq" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        if [ $prev -ne $current ]; then
                            draw_option $prev
                            draw_option $current
                        fi
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        if [ $prev -ne $current ]; then
                            draw_option $prev
                            draw_option $current
                        fi
                        ;;
                esac
                ;;
        esac
    done
}

# Configure TLDR settings
configure_tldr_settings() {
    show_cursor
    exit_alt_screen

    echo ""
    echo -e "${BLUE}TLDR Code Analysis Settings${NC}"
    echo ""

    # Check if llm-tldr is installed
    local tldr_installed=false
    if command -v tldr &> /dev/null && tldr --help 2>&1 | grep -q "warm\|semantic"; then
        tldr_installed=true
        local version=$(tldr --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓${NC} llm-tldr installed: $version"
    else
        echo -e "  ${RED}✗${NC} llm-tldr not installed"
        echo ""
        echo -e "  ${DIM}To install llm-tldr:${NC}"
        echo -e "  ${CYAN}pip install llm-tldr${NC}"
        echo ""
        echo -e "  ${DIM}llm-tldr provides 95% token reduction through code analysis.${NC}"
        echo -e "  ${DIM}Learn more: https://github.com/parcadei/llm-tldr${NC}"
        echo ""
        read -p "Press Enter to continue..."
        enter_alt_screen
        hide_cursor
        return
    fi

    # Get current defaults from settings
    local default_enabled=$(jq -r '.tldr.defaultEnabled // false' "$SETTINGS_FILE" 2>/dev/null)
    local default_auto_warm=$(jq -r '.tldr.defaultAutoWarm // true' "$SETTINGS_FILE" 2>/dev/null)
    local warm_timeout=$(jq -r '.tldr.warmTimeout // 300' "$SETTINGS_FILE" 2>/dev/null)

    echo ""
    echo -e "${BLUE}Default Settings for New Projects${NC}"
    echo ""

    # Toggle default enabled
    echo -e "  Current default enabled: ${CYAN}$default_enabled${NC}"
    read -p "  Enable TLDR by default for new projects? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        default_enabled="true"
    else
        default_enabled="false"
    fi

    # Toggle default auto-warm
    echo ""
    echo -e "  Current auto-warm default: ${CYAN}$default_auto_warm${NC}"
    read -p "  Auto-warm indexes by default? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        default_auto_warm="false"
    else
        default_auto_warm="true"
    fi

    # Warm timeout
    echo ""
    echo -e "  Current warm timeout: ${CYAN}${warm_timeout}s${NC}"
    read -p "  Warm timeout in seconds [$warm_timeout]: " new_timeout
    [ -n "$new_timeout" ] && warm_timeout="$new_timeout"

    # Save settings
    local temp=$(mktemp)
    jq ".tldr = {
        \"installed\": $tldr_installed,
        \"defaultEnabled\": $default_enabled,
        \"defaultAutoWarm\": $default_auto_warm,
        \"warmTimeout\": $warm_timeout
    }" "$SETTINGS_FILE" > "$temp" && mv "$temp" "$SETTINGS_FILE"

    echo ""
    echo -e "${GREEN}✓${NC} TLDR settings saved"
    echo ""

    # Offer to test
    read -p "Test TLDR with current directory? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}Running: tldr tree .${NC}"
        tldr tree . 2>&1 | head -20
        echo ""
    fi

    read -p "Press Enter to continue..."

    enter_alt_screen
    hide_cursor
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

# Show current settings - clean style
show_settings() {
    echo ""
    echo -e "    ${TEXT}${BOLD}Current Settings${NC}"
    echo ""

    local level=$(get_delegation_level)
    local level_name=$(get_delegation_name)
    local level_desc=$(jq -r ".delegation.levels[\"$level\"].description" "$SETTINGS_FILE")

    echo -e "    ${ACCENT}${BOLD}Delegation Strategy${NC}"
    echo -e "     Level $level/4 ${TEXT_MUTED}$level_name${NC}"
    echo -e "     ${TEXT_DIM}$level_desc${NC}"
    echo ""

    echo -e "    ${ACCENT}${BOLD}Delegation Behavior${NC}"
    local visible=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
    local branches=$(jq -r '.delegation.use_branches // true' "$SETTINGS_FILE")

    local vis_indicator="○"
    local branch_indicator="○"
    [ "$visible" = "true" ] && vis_indicator="${SUCCESS}●${NC}"
    [ "$branches" = "true" ] && branch_indicator="${SUCCESS}●${NC}"

    echo -e "     $vis_indicator ${TEXT}Visible delegation${NC}"
    echo -e "     $branch_indicator ${TEXT}Branch isolation${NC}"
    echo ""

    echo -e "    ${ACCENT}${BOLD}AI Tools${NC}"
    local tools=$(jq -r '.ai_tools | to_entries[] | "\(.key):\(.value.enabled):\(.value.installed):\(.value.name)"' "$SETTINGS_FILE")

    while IFS=: read -r id enabled installed name; do
        local checkbox="○"
        [ "$enabled" = "true" ] && checkbox="${SUCCESS}●${NC}"

        local install_status="${TEXT_MUTED}not found${NC}"
        [ "$installed" = "true" ] && install_status="${SUCCESS}installed${NC}"

        echo -e "     $checkbox ${TEXT}$name${NC} ${TEXT_DIM}$install_status${NC}"
    done <<< "$tools"

    echo ""
}

# Main settings menu - polished style
main_menu() {
    # Menu items: id, label, description
    local -a menu_ids=("delegation" "tools" "custom" "behavior" "tldr" "apply" "show" "reset" "done")
    local -a menu_labels=(
        "Delegation Level"
        "AI Tools"
        "Add Custom Tool"
        "Delegation Behavior"
        "TLDR Settings"
        "Apply Settings"
        "Show Settings"
        "Reset to Defaults"
        "Done"
    )
    local -a menu_descs=(
        "Set how much Claude delegates"
        "Enable/disable AI tools"
        "Add a custom command"
        "Visibility and branches"
        "Code analysis tool config"
        "Update CLAUDE.md"
        "Display current config"
        "Reset all settings"
        "Save and exit"
    )
    local total=${#menu_ids[@]}
    local current=0
    local ITEMS_ROW=9

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header with current config
    draw_header() {
        local level=$(get_delegation_level)
        local level_name=$(get_delegation_name)
        local enabled_count=$(jq '[.ai_tools[] | select(.enabled == true)] | length' "$SETTINGS_FILE")

        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}Settings${NC}                                                                   ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Level $level ($level_name) · $enabled_count tools enabled${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Options${NC}"
    }

    # Draw a single menu item
    draw_item() {
        local i=$1
        local row=$((ITEMS_ROW + i))

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} ${menu_labels[$i]} ${NC}${PRIMARY_BG}${PRIMARY_FG} ${menu_descs[$i]} ${NC}"
        else
            echo -e "     ${TEXT}${menu_labels[$i]}${NC} ${TEXT_MUTED}${menu_descs[$i]}${NC}"
        fi
    }

    # Draw all items
    draw_all_items() {
        for ((i=0; i<total; i++)); do
            draw_item $i
        done
    }

    # No separate description - it's inline now
    draw_description() {
        :  # No-op, description is inline
    }

    # Initial draw
    draw_header
    draw_all_items
    draw_description

    while true; do
        IFS= read -rsn1 key

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
                    tldr)
                        configure_tldr_settings
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
                if [ -z "$seq" ]; then
                    # Just escape - save and exit
                    goto_row $((ITEMS_ROW + total + 2))
                    clear_below
                    generate_claude_md
                    echo ""
                    echo -e "${SUCCESS}Settings saved!${NC}"
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    exit 0
                fi
                local prev=$current
                case "$seq" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        if [ $prev -ne $current ]; then
                            draw_item $prev
                            draw_item $current
                        fi
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        if [ $prev -ne $current ]; then
                            draw_item $prev
                            draw_item $current
                        fi
                        ;;
                esac
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
