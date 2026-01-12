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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

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

# Show header
show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}CLAUDE WORKSPACE SETTINGS${NC}                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Interactive slider for delegation level
delegation_slider() {
    local current=$(get_delegation_level)
    local max=4

    # Hide cursor
    tput civis
    trap 'tput cnorm' EXIT

    draw_slider() {
        show_header
        echo -e "${BOLD}Delegation Strategy${NC}"
        echo -e "${DIM}How much should Claude delegate to external AI tools?${NC}"
        echo ""

        # Draw slider
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

        # Labels
        echo -e "  ${DIM}Off${NC}                           ${DIM}Max${NC}"
        echo ""

        # Current level info
        local name=$(jq -r ".delegation.levels[\"$current\"].name" "$SETTINGS_FILE")
        local desc=$(jq -r ".delegation.levels[\"$current\"].description" "$SETTINGS_FILE")

        echo -e "  ${BOLD}Level $current: $name${NC}"
        echo -e "  ${DIM}$desc${NC}"
        echo ""

        # Level descriptions
        echo -e "${BLUE}Levels:${NC}"
        for ((i=0; i<=max; i++)); do
            local lname=$(jq -r ".delegation.levels[\"$i\"].name" "$SETTINGS_FILE")
            local ldesc=$(jq -r ".delegation.levels[\"$i\"].description" "$SETTINGS_FILE")
            if [ $i -eq $current ]; then
                echo -e "  ${GREEN}▶ [$i] $lname${NC}"
                echo -e "    ${DIM}$ldesc${NC}"
            else
                echo -e "  ${DIM}  [$i] $lname${NC}"
            fi
        done

        echo ""
        echo -e "  ${DIM}←/→: Adjust   Enter: Confirm   q: Cancel${NC}"
    }

    draw_slider

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                return 1
                ;;
            "")  # Enter
                # Save setting
                local temp=$(mktemp)
                jq ".delegation.level = $current" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                return 0
                ;;
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[D')  # Left
                        ((current--))
                        [ $current -lt 0 ] && current=0
                        draw_slider
                        ;;
                    '[C')  # Right
                        ((current++))
                        [ $current -gt $max ] && current=$max
                        draw_slider
                        ;;
                esac
                ;;
            [0-4])  # Direct number input
                current=$key
                draw_slider
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

    # Hide cursor
    tput civis
    trap 'tput cnorm' EXIT

    draw_tools_menu() {
        show_header
        echo -e "${BOLD}External AI Tools${NC}"
        echo -e "${DIM}Configure which AI tools Claude can delegate to${NC}"
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Space: Toggle   Enter: Done   a: Auto-detect${NC}"
        echo ""

        for ((i=0; i<total; i++)); do
            local tool="${tools[$i]}"
            local name=$(jq -r ".ai_tools.$tool.name" "$SETTINGS_FILE")
            local cmd=$(jq -r ".ai_tools.$tool.command" "$SETTINGS_FILE")
            local enabled=$(jq -r ".ai_tools.$tool.enabled" "$SETTINGS_FILE")
            local installed=$(jq -r ".ai_tools.$tool.installed" "$SETTINGS_FILE")

            local checkbox="[ ]"
            local status=""

            if [ "$enabled" = "true" ]; then
                checkbox="${GREEN}[✓]${NC}"
            fi

            if [ "$installed" = "true" ]; then
                status="${GREEN}(installed)${NC}"
            else
                status="${YELLOW}(not found)${NC}"
            fi

            if [ $i -eq $current ]; then
                echo -e "  ${BOLD}▶ $checkbox $name${NC} $status"
                echo -e "    ${DIM}Command: $cmd${NC}"
            else
                echo -e "    $checkbox $name $status"
            fi
        done

        echo ""

        # Show enabled count
        local enabled_count=$(jq '[.ai_tools[] | select(.enabled == true)] | length' "$SETTINGS_FILE")
        echo -e "  ${BLUE}Enabled: $enabled_count / $total${NC}"
    }

    draw_tools_menu

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                return 1
                ;;
            "")  # Enter
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
                draw_tools_menu
                ;;
            " ")  # Space - toggle
                local tool="${tools[$current]}"
                local enabled=$(jq -r ".ai_tools.$tool.enabled" "$SETTINGS_FILE")
                local new_val="true"
                [ "$enabled" = "true" ] && new_val="false"

                local temp=$(mktemp)
                jq ".ai_tools.$tool.enabled = $new_val" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                draw_tools_menu
                ;;
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # Up
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        draw_tools_menu
                        ;;
                    '[B')  # Down
                        ((current++))
                        [ $current -ge $total ] && current=0
                        draw_tools_menu
                        ;;
                esac
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
    while true; do
        show_header
        echo -e "${BOLD}Delegation Behavior${NC}"
        echo -e "${DIM}Configure how delegated tasks are handled${NC}"
        echo ""

        local visible=$(jq -r '.delegation.visible_by_default // false' "$SETTINGS_FILE")
        local branches=$(jq -r '.delegation.use_branches // true' "$SETTINGS_FILE")

        local visible_status="${RED}Off${NC}"
        local branches_status="${RED}Off${NC}"
        [ "$visible" = "true" ] && visible_status="${GREEN}On${NC}"
        [ "$branches" = "true" ] && branches_status="${GREEN}On${NC}"

        echo -e "  ${CYAN}[1]${NC} Visible delegation: $visible_status"
        echo -e "      ${DIM}Open split terminal to see AI working${NC}"
        echo ""
        echo -e "  ${CYAN}[2]${NC} Branch isolation: $branches_status"
        echo -e "      ${DIM}Create feature branches for each delegation${NC}"
        echo ""
        echo -e "  ${CYAN}[q]${NC} Back"
        echo ""

        read -p "Choice: " -n 1 -r choice
        echo ""

        case $choice in
            1)
                local new_val="true"
                [ "$visible" = "true" ] && new_val="false"
                local temp=$(mktemp)
                jq ".delegation.visible_by_default = $new_val" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                ;;
            2)
                local new_val="true"
                [ "$branches" = "true" ] && new_val="false"
                local temp=$(mktemp)
                jq ".delegation.use_branches = $new_val" "$SETTINGS_FILE" > "$temp"
                mv "$temp" "$SETTINGS_FILE"
                ;;
            q|Q)
                return
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
    while true; do
        show_header

        local level=$(get_delegation_level)
        local level_name=$(get_delegation_name)
        local enabled_count=$(jq '[.ai_tools[] | select(.enabled == true)] | length' "$SETTINGS_FILE")

        echo -e "${BOLD}Current Configuration:${NC}"
        echo -e "  Delegation: Level $level ($level_name)"
        echo -e "  AI Tools: $enabled_count enabled"
        echo ""

        echo -e "${BOLD}Options:${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC} Adjust delegation level"
        echo -e "  ${CYAN}[2]${NC} Configure AI tools"
        echo -e "  ${CYAN}[3]${NC} Add custom AI tool"
        echo -e "  ${CYAN}[4]${NC} Delegation behavior (visibility, branches)"
        echo -e "  ${CYAN}[5]${NC} Apply settings (update CLAUDE.md)"
        echo -e "  ${CYAN}[6]${NC} Show current settings"
        echo -e "  ${CYAN}[r]${NC} Reset to defaults"
        echo -e "  ${CYAN}[q]${NC} Done"
        echo ""
        read -p "Choice: " -n 1 -r choice
        echo ""

        case $choice in
            1)
                delegation_slider
                ;;
            2)
                configure_ai_tools
                ;;
            3)
                add_custom_tool
                ;;
            4)
                configure_delegation_options
                ;;
            5)
                generate_claude_md
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                show_settings
                read -p "Press Enter to continue..."
                ;;
            r|R)
                echo ""
                read -p "Reset all settings to defaults? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "$DEFAULT_SETTINGS" | jq '.' > "$SETTINGS_FILE"
                    detect_installed_tools
                    echo -e "${GREEN}✓${NC} Settings reset"
                fi
                read -p "Press Enter to continue..."
                ;;
            q|Q)
                # Apply settings on exit
                generate_claude_md
                echo ""
                echo -e "${GREEN}Settings saved!${NC}"
                echo ""
                exit 0
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
