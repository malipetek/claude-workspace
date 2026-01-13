#!/bin/bash

#==============================================================================
#  WORKSPACE INSTRUCTIONS LIBRARY - CLAUDE.md generation for dev processes
#==============================================================================
#
#  Functions for generating and updating CLAUDE.md with workspace-specific
#  instructions about dev process logs, watch mode, and how Claude should
#  interact with the captured terminal output.
#
#  USAGE:
#    source ~/.claude-workspace/scripts/lib/workspace-instructions.sh
#
#    update_workspace_instructions "/path/to/project"
#
#==============================================================================

# Colors (if not already defined)
: "${NC:=\033[0m}"
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${DIM:=\033[2m}"

#==============================================================================
# Instruction Generation
#==============================================================================

# Generate dev process instructions for CLAUDE.md
generate_dev_process_instructions() {
    local project_name="$1"

    cat << EOF

## Workspace Dev Processes

This project runs with **live dev processes in watch mode**. All terminals are captured and logs are available for you to read.

### Key Points

1. **No manual builds needed** - All processes run in watch mode and auto-reload on file changes
2. **Logs are captured** - All terminal output is saved to \`~/.claude-workspace/dev-logs/${project_name}/\`
3. **Check logs after changes** - After editing files, check the logs to verify changes compiled/reloaded correctly

### Checking Dev Process Logs

**Quick summary of all processes:**
\`\`\`bash
~/.claude-workspace/scripts/dev-logs.sh summary
\`\`\`

**Check specific process logs:**
\`\`\`bash
# Last 50 lines from a process
~/.claude-workspace/scripts/dev-logs.sh tail <process_name>

# Last 100 lines
~/.claude-workspace/scripts/dev-logs.sh tail <process_name> 100

# Only error lines
~/.claude-workspace/scripts/dev-logs.sh errors <process_name>

# Recent errors across all processes
~/.claude-workspace/scripts/dev-logs.sh recent
\`\`\`

**List available processes:**
\`\`\`bash
~/.claude-workspace/scripts/dev-logs.sh list
\`\`\`

### After Making Code Changes

1. **Wait 1-2 seconds** for hot reload to trigger
2. **Check the logs** to verify the change compiled successfully:
   \`\`\`bash
   ~/.claude-workspace/scripts/dev-logs.sh summary
   \`\`\`
3. **If errors appear**, check details:
   \`\`\`bash
   ~/.claude-workspace/scripts/dev-logs.sh errors
   \`\`\`

### Common Process Names

Typical process names in this workspace:
- \`frontend\` - Frontend dev server (Next.js, Vite, etc.)
- \`backend\` - Backend API server
- \`database\` - Database or Docker services
- \`types\` - TypeScript compiler in watch mode
- \`worker\` - Background job processor

### IMPORTANT: DO NOT

- **DO NOT** run \`npm run build\` or \`npm run dev\` - processes are already running
- **DO NOT** ask the user to check terminal output - read the logs yourself
- **DO NOT** assume builds need to be triggered - watch mode handles this automatically

### Log File Location

Direct log file paths:
\`\`\`
~/.claude-workspace/dev-logs/${project_name}/<process>.log
\`\`\`

You can also read these directly with the Read tool:
\`\`\`bash
# Example: read the last 100 lines of frontend logs
~/.claude-workspace/scripts/dev-logs.sh tail frontend 100
\`\`\`

EOF
}

#==============================================================================
# CLAUDE.md Management
#==============================================================================

# Update project CLAUDE.md with workspace dev process instructions
# Usage: update_workspace_instructions "/path/to/project"
update_workspace_instructions() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    local claude_md="$project_path/CLAUDE.md"
    local marker="## Workspace Dev Processes"

    # Generate instructions
    local instructions
    instructions=$(generate_dev_process_instructions "$project_name")

    if [ -f "$claude_md" ]; then
        # Check if already has workspace section
        if grep -q "$marker" "$claude_md"; then
            # Replace existing section
            local temp
            temp=$(mktemp)
            awk -v marker="$marker" -v new="$instructions" '
                BEGIN { skip=0 }
                $0 ~ marker { skip=1; print new; next }
                skip && /^## / { skip=0 }
                !skip { print }
            ' "$claude_md" > "$temp" && mv "$temp" "$claude_md"
        else
            # Append to existing file
            echo "$instructions" >> "$claude_md"
        fi
    else
        # Create new file with header
        cat > "$claude_md" << 'HEADER'
# Project Instructions

This file contains instructions for Claude when working on this project.
HEADER
        echo "$instructions" >> "$claude_md"
    fi

    echo -e "${GREEN}✓${NC} Updated CLAUDE.md with workspace instructions"
}

# Remove workspace instructions from CLAUDE.md
remove_workspace_instructions() {
    local project_path="$1"
    local claude_md="$project_path/CLAUDE.md"
    local marker="## Workspace Dev Processes"

    if [ -f "$claude_md" ] && grep -q "$marker" "$claude_md"; then
        local temp
        temp=$(mktemp)
        awk -v marker="$marker" '
            BEGIN { skip=0 }
            $0 ~ marker { skip=1; next }
            skip && /^## / { skip=0 }
            !skip { print }
        ' "$claude_md" > "$temp" && mv "$temp" "$claude_md"

        echo -e "${GREEN}✓${NC} Removed workspace instructions from CLAUDE.md"
    fi
}

# Check if project has workspace instructions
has_workspace_instructions() {
    local project_path="$1"
    local claude_md="$project_path/CLAUDE.md"
    local marker="## Workspace Dev Processes"

    [ -f "$claude_md" ] && grep -q "$marker" "$claude_md"
}

#==============================================================================
# Utility Functions
#==============================================================================

# Get process names from config
get_process_names() {
    local project_path="$1"
    local config_file="$project_path/.claude-workspace.json"

    if [ -f "$config_file" ]; then
        jq -r '.processes[].name' "$config_file" 2>/dev/null
    fi
}

# Check if project has dev processes configured
has_dev_processes() {
    local project_path="$1"
    local config_file="$project_path/.claude-workspace.json"

    if [ -f "$config_file" ]; then
        local count
        count=$(jq '.processes | length // 0' "$config_file" 2>/dev/null)
        [ "$count" -gt 0 ]
    else
        return 1
    fi
}

# Print workspace instructions status
print_workspace_status() {
    local project_path="$1"

    echo -e "${BLUE}Workspace Status${NC}"
    echo ""

    if has_dev_processes "$project_path"; then
        local process_names
        process_names=$(get_process_names "$project_path" | tr '\n' ', ' | sed 's/,$//')
        echo -e "  ${GREEN}●${NC} Dev processes: $process_names"
    else
        echo -e "  ${DIM}○${NC} No dev processes configured"
    fi

    if has_workspace_instructions "$project_path"; then
        echo -e "  ${GREEN}●${NC} CLAUDE.md has workspace instructions"
    else
        echo -e "  ${DIM}○${NC} CLAUDE.md missing workspace instructions"
    fi

    echo ""
}
