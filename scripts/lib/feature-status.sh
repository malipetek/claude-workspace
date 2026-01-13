#!/bin/bash

#==============================================================================
#  FEATURE STATUS LIBRARY - Display workspace feature status and warnings
#==============================================================================
#
#  Functions for displaying what features are available, configured, and
#  what's missing. Shows clear warnings so users know what to fix.
#
#  USAGE:
#    source ~/.claude-workspace/scripts/lib/feature-status.sh
#
#    show_feature_status "/path/to/project"
#
#==============================================================================

# Colors (if not already defined)
: "${NC:=\033[0m}"
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${DIM:=\033[2m}"
: "${BOLD:=\033[1m}"

#==============================================================================
# Feature Detection
#==============================================================================

# Check if AI delegation is configured
check_delegation_status() {
    local project_path="$1"
    local global_claude_md="$HOME/.claude/CLAUDE.md"

    # Check if delegation scripts exist
    if [ ! -f "$HOME/.claude-workspace/scripts/delegate.sh" ]; then
        echo "not_installed"
        return
    fi

    # Check if any AI CLI is available
    local ai_available=false
    if command -v gemini &>/dev/null; then
        ai_available=true
    fi
    if command -v opencode &>/dev/null; then
        ai_available=true
    fi
    if command -v aider &>/dev/null; then
        ai_available=true
    fi

    if [ "$ai_available" = false ]; then
        echo "no_ai_cli"
        return
    fi

    # Check if instructions are in CLAUDE.md
    if [ -f "$global_claude_md" ] && grep -q "AI Delegation" "$global_claude_md"; then
        echo "configured"
    else
        echo "not_configured"
    fi
}

# Check TLDR status comprehensively
check_tldr_status() {
    local project_path="$1"
    local config_file="$project_path/.claude-workspace.json"

    # Check if enabled in config
    local enabled="false"
    if [ -f "$config_file" ]; then
        enabled=$(jq -r '.tldr.enabled // false' "$config_file" 2>/dev/null)
    fi

    if [ "$enabled" != "true" ]; then
        echo "disabled"
        return
    fi

    # Check if llm-tldr is installed
    if ! command -v tldr &>/dev/null; then
        echo "not_installed"
        return
    fi

    # Verify it's llm-tldr (not man-pages tldr)
    if ! tldr --help 2>&1 | grep -q "warm\|semantic\|context"; then
        echo "wrong_tldr"
        return
    fi

    # Check if MCP is configured in Claude settings
    local claude_settings="$project_path/.claude/settings.json"
    if [ ! -f "$claude_settings" ] || ! jq -e '.mcpServers.tldr' "$claude_settings" &>/dev/null; then
        echo "mcp_not_configured"
        return
    fi

    # Check if indexes exist
    if [ ! -d "$project_path/.tldr" ]; then
        echo "no_indexes"
        return
    fi

    echo "ready"
}

# Check dev-logs status
check_devlogs_status() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    local config_file="$project_path/.claude-workspace.json"

    # Check if processes are configured
    if [ ! -f "$config_file" ]; then
        echo "no_config"
        return
    fi

    local process_count=$(jq '.processes | length // 0' "$config_file" 2>/dev/null)
    if [ "$process_count" -eq 0 ]; then
        echo "no_processes"
        return
    fi

    # Check if CLAUDE.md has workspace instructions
    local claude_md="$project_path/CLAUDE.md"
    if [ ! -f "$claude_md" ] || ! grep -q "## Workspace Dev Processes" "$claude_md"; then
        echo "no_instructions"
        return
    fi

    echo "ready"
}

#==============================================================================
# Status Display
#==============================================================================

# Show comprehensive feature status with warnings
show_feature_status() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    local config_file="$project_path/.claude-workspace.json"
    local has_warnings=false

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║  WORKSPACE FEATURE STATUS                                                    ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Dev Process Logs
    # ─────────────────────────────────────────────────────────────────────────
    local devlogs_status=$(check_devlogs_status "$project_path")

    echo -e "${BOLD}Dev Process Logs${NC}"
    case "$devlogs_status" in
        ready)
            local process_count=$(jq '.processes | length' "$config_file" 2>/dev/null)
            echo -e "  ${GREEN}✓${NC} Ready - $process_count processes configured"
            echo -e "  ${DIM}Claude will check logs at: ~/.claude-workspace/dev-logs/$project_name/${NC}"
            ;;
        no_config)
            echo -e "  ${DIM}○${NC} No .claude-workspace.json found"
            ;;
        no_processes)
            echo -e "  ${DIM}○${NC} No dev processes configured"
            ;;
        no_instructions)
            echo -e "  ${YELLOW}⚠${NC} Missing CLAUDE.md instructions"
            echo -e "    ${DIM}Run: update_workspace_instructions \"$project_path\"${NC}"
            has_warnings=true
            ;;
    esac
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # TLDR Code Analysis
    # ─────────────────────────────────────────────────────────────────────────
    local tldr_status=$(check_tldr_status "$project_path")

    echo -e "${BOLD}TLDR Code Analysis${NC}"
    case "$tldr_status" in
        ready)
            local index_count=$(find "$project_path/.tldr" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
            echo -e "  ${GREEN}✓${NC} Ready - $index_count files indexed, MCP configured"
            ;;
        disabled)
            echo -e "  ${DIM}○${NC} Not enabled for this project"
            echo -e "    ${DIM}Enable in .claude-workspace.json: \"tldr\": {\"enabled\": true}${NC}"
            ;;
        not_installed)
            echo -e "  ${RED}✗${NC} ENABLED but llm-tldr not installed!"
            echo -e "    ${YELLOW}Install with: pip install llm-tldr${NC}"
            has_warnings=true
            ;;
        wrong_tldr)
            echo -e "  ${RED}✗${NC} Wrong 'tldr' command (man-pages tldr, not llm-tldr)"
            echo -e "    ${YELLOW}Install llm-tldr: pip install llm-tldr${NC}"
            has_warnings=true
            ;;
        mcp_not_configured)
            echo -e "  ${YELLOW}⚠${NC} MCP server not configured for Claude Code"
            echo -e "    ${DIM}Run workspace again or manually configure .claude/settings.json${NC}"
            has_warnings=true
            ;;
        no_indexes)
            echo -e "  ${YELLOW}⚠${NC} No indexes found - warming now..."
            has_warnings=true
            ;;
    esac
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # AI Delegation
    # ─────────────────────────────────────────────────────────────────────────
    local delegation_status=$(check_delegation_status "$project_path")

    echo -e "${BOLD}AI Delegation${NC}"
    case "$delegation_status" in
        configured)
            # List available AIs
            local available_ais=""
            command -v gemini &>/dev/null && available_ais="${available_ais}gemini "
            command -v opencode &>/dev/null && available_ais="${available_ais}opencode "
            command -v aider &>/dev/null && available_ais="${available_ais}aider "
            echo -e "  ${GREEN}✓${NC} Ready - Available: ${available_ais}"
            ;;
        not_installed)
            echo -e "  ${DIM}○${NC} Delegation scripts not found"
            ;;
        no_ai_cli)
            echo -e "  ${YELLOW}⚠${NC} No AI CLIs found (gemini, opencode, aider)"
            echo -e "    ${DIM}Install at least one to enable delegation${NC}"
            ;;
        not_configured)
            echo -e "  ${YELLOW}⚠${NC} Instructions not in ~/.claude/CLAUDE.md"
            echo -e "    ${DIM}Run: claude-workspace settings → AI Delegation${NC}"
            has_warnings=true
            ;;
    esac
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Summary warnings
    # ─────────────────────────────────────────────────────────────────────────
    if [ "$has_warnings" = true ]; then
        echo "─────────────────────────────────────────────────────────────────────────────"
        echo -e "${YELLOW}Some features need attention. See warnings above.${NC}"
        echo ""
    fi

    return 0
}

# Show a compact one-line status (for non-verbose mode)
show_compact_status() {
    local project_path="$1"
    local statuses=""

    # Dev logs
    local devlogs_status=$(check_devlogs_status "$project_path")
    if [ "$devlogs_status" = "ready" ]; then
        statuses="${statuses}${GREEN}●${NC}DevLogs "
    elif [ "$devlogs_status" != "no_config" ] && [ "$devlogs_status" != "no_processes" ]; then
        statuses="${statuses}${YELLOW}●${NC}DevLogs "
    fi

    # TLDR
    local tldr_status=$(check_tldr_status "$project_path")
    if [ "$tldr_status" = "ready" ]; then
        statuses="${statuses}${GREEN}●${NC}TLDR "
    elif [ "$tldr_status" != "disabled" ]; then
        statuses="${statuses}${YELLOW}●${NC}TLDR "
    fi

    # Delegation
    local delegation_status=$(check_delegation_status "$project_path")
    if [ "$delegation_status" = "configured" ]; then
        statuses="${statuses}${GREEN}●${NC}Delegation "
    elif [ "$delegation_status" != "not_installed" ]; then
        statuses="${statuses}${YELLOW}●${NC}Delegation "
    fi

    if [ -n "$statuses" ]; then
        echo -e "Features: $statuses"
    fi
}
