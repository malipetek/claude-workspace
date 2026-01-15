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

## ⚠️ REQUIRED: Workspace Dev Process Integration

**THIS IS CRITICAL**: This workspace has live dev processes running in watch mode. You MUST use the dev-logs system to check for errors instead of running builds or asking the user.

### 🔴 MANDATORY BEHAVIOR

After EVERY code change you make:
1. **WAIT 2 seconds** for hot-reload
2. **RUN THIS COMMAND** to check for errors:
   \`\`\`bash
   ~/.claude-workspace/scripts/dev-logs.sh summary
   \`\`\`
3. If errors exist, check details with:
   \`\`\`bash
   ~/.claude-workspace/scripts/dev-logs.sh errors
   \`\`\`

### 🚫 NEVER DO THESE

- ❌ **NEVER** run \`npm run build\`, \`npm run dev\`, \`pnpm build\`, etc. - processes are ALREADY running
- ❌ **NEVER** ask the user to "check the terminal" or "look at the output" - READ THE LOGS YOURSELF
- ❌ **NEVER** assume you need to start or trigger builds - watch mode auto-compiles on save

### ✅ ALWAYS DO THESE

- ✅ **ALWAYS** check \`dev-logs.sh summary\` after editing code
- ✅ **ALWAYS** read error details from logs before asking user for help
- ✅ **ALWAYS** use the log commands below to see build output

### Dev Log Commands

\`\`\`bash
# Quick status - ARE THERE ERRORS? (run this after every change)
~/.claude-workspace/scripts/dev-logs.sh summary

# See all errors with context
~/.claude-workspace/scripts/dev-logs.sh errors

# Tail a specific process (frontend, backend, etc.)
~/.claude-workspace/scripts/dev-logs.sh tail frontend 100

# List all available processes
~/.claude-workspace/scripts/dev-logs.sh list
\`\`\`

### Log Location

Logs are at: \`~/.claude-workspace/dev-logs/${project_name}/<process>.log\`

### Why This Matters

The dev processes are running in separate terminal panes with captured output. Running builds would:
1. Duplicate running processes (port conflicts)
2. Waste time when errors are already visible in logs
3. Frustrate the user who set up this workflow

**USE THE LOGS. THEY HAVE EVERYTHING YOU NEED.**

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
    # Match the actual header in the generated content
    local marker="## ⚠️ REQUIRED: Workspace Dev Process Integration"

    # Generate instructions
    local instructions
    instructions=$(generate_dev_process_instructions "$project_name")

    if [ -f "$claude_md" ]; then
        # Check if already has workspace section (check for marker or old marker)
        if grep -q "Workspace Dev Process" "$claude_md"; then
            # Replace existing section - remove ALL workspace sections first
            local temp
            temp=$(mktemp)
            awk '
                BEGIN { skip=0 }
                /## .*Workspace Dev Process/ { skip=1; next }
                skip && /^## / { skip=0 }
                !skip { print }
            ' "$claude_md" > "$temp" && mv "$temp" "$claude_md"
            # Now append fresh instructions
            echo "$instructions" >> "$claude_md"
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
