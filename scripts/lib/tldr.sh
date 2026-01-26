#!/bin/bash

#==============================================================================
#  TLDR LIBRARY - llm-tldr integration for Claude Workspace
#==============================================================================
#
#  Functions for detecting, configuring, and using llm-tldr code analysis.
#  Provides 95% token reduction through structured code analysis.
#
#  USAGE:
#    source ~/.claude-workspace/scripts/lib/tldr.sh
#
#    detect_tldr_installation
#    warm_tldr_indexes "/path/to/project"
#    configure_tldr_mcp "/path/to/project"
#
#==============================================================================

# Colors (if not already defined)
: "${NC:=\033[0m}"
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${DIM:=\033[2m}"

# Default settings
TLDR_WARM_TIMEOUT="${TLDR_WARM_TIMEOUT:-300}"
TLDR_DEFAULT_MODEL="BAAI/bge-base-en-v1.5"
TLDR_FALLBACK_MODEL="sentence-transformers/all-MiniLM-L6-v2"

# Get configured embedding model
get_tldr_embedding_model() {
    local settings_file="$HOME/.claude-workspace/settings.json"
    if [ -f "$settings_file" ]; then
        local saved_model=$(jq -r '.tldr.embeddingModel // empty' "$settings_file" 2>/dev/null)
        if [ -n "$saved_model" ]; then
            echo "$saved_model"
            return
        fi
    fi
    echo "$TLDR_DEFAULT_MODEL"
}

#==============================================================================
# Detection Functions
#==============================================================================

# Check if llm-tldr is installed (not the man-pages tldr)
# Returns 0 if installed, 1 if not
detect_tldr_installation() {
    if ! command -v tldr &> /dev/null; then
        return 1
    fi

    # Verify it's llm-tldr by checking for specific commands
    if tldr --help 2>&1 | grep -q "warm\|semantic\|context"; then
        return 0
    fi

    return 1
}

# Get tldr version if installed
get_tldr_version() {
    if detect_tldr_installation; then
        tldr --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Check if project has tldr enabled
is_tldr_enabled() {
    local project_path="$1"
    local config_file="$project_path/.claude-workspace.json"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local enabled
    enabled=$(jq -r '.tldr.enabled // false' "$config_file" 2>/dev/null)

    [ "$enabled" = "true" ]
}

# Check if project has tldr indexes
has_tldr_indexes() {
    local project_path="$1"
    [ -d "$project_path/.tldr" ]
}

#==============================================================================
# Index Management
#==============================================================================

# Warm tldr indexes for a project
# Usage: warm_tldr_indexes "/path/to/project" [--quiet]
warm_tldr_indexes() {
    local project_path="$1"
    local quiet="${2:-}"
    local config_file="$project_path/.claude-workspace.json"

    # Check if tldr is installed
    if ! detect_tldr_installation; then
        [ -z "$quiet" ] && echo -e "${YELLOW}Warning: TLDR enabled but 'tldr' command not found${NC}"
        [ -z "$quiet" ] && echo -e "${DIM}Install with: pip install llm-tldr${NC}"
        return 1
    fi

    # Check if auto-warm is enabled (default true)
    local auto_warm="true"
    if [ -f "$config_file" ]; then
        auto_warm=$(jq -r '.tldr.autoWarm // true' "$config_file" 2>/dev/null)
    fi

    if [ "$auto_warm" != "true" ]; then
        [ -z "$quiet" ] && echo -e "${DIM}TLDR auto-warm disabled for this project${NC}"
        return 0
    fi

    [ -z "$quiet" ] && echo -e "${BLUE}Warming TLDR indexes...${NC}"
    [ -z "$quiet" ] && echo -e "${DIM}This may take a moment on first run${NC}"

    # Ensure .tldrignore exists FIRST (before any tldr commands)
    ensure_tldr_ignore "$project_path"

    # Also ensure .gitignore has node_modules (llm-tldr may use it)
    ensure_gitignore_excludes "$project_path"

    # Clean any existing broken indexes that include node_modules
    if [ -d "$project_path/.tldr" ]; then
        local bad_indexes=$(find "$project_path/.tldr" -type f -name "*.json" 2>/dev/null | xargs grep -l "node_modules" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$bad_indexes" -gt 0 ]; then
            [ -z "$quiet" ] && echo -e "${YELLOW}Cleaning $bad_indexes corrupted indexes...${NC}"
            rm -rf "$project_path/.tldr"
        fi
    fi

    # Detect project language (with monorepo support)
    local lang_flag=""
    local has_ts_files=$(find "$project_path" -name "*.ts" -o -name "*.tsx" 2>/dev/null | grep -v node_modules | head -1)
    local has_tsconfig=$(find "$project_path" -name "tsconfig.json" -not -path "*/node_modules/*" 2>/dev/null | head -1)

    if [ -f "$project_path/tsconfig.json" ] || [ -n "$has_tsconfig" ] || [ -n "$has_ts_files" ]; then
        lang_flag="--lang typescript"
    elif [ -f "$project_path/package.json" ]; then
        lang_flag="--lang javascript"
    elif [ -f "$project_path/setup.py" ] || [ -f "$project_path/pyproject.toml" ]; then
        lang_flag="--lang python"
    elif [ -f "$project_path/Cargo.toml" ]; then
        lang_flag="--lang rust"
    elif [ -f "$project_path/go.mod" ]; then
        lang_flag="--lang go"
    fi

    [ -z "$quiet" ] && [ -n "$lang_flag" ] && echo -e "${DIM}Detected language: ${lang_flag#--lang }${NC}"

    # Run warm with timeout (builds call graph cache)
    local start_time=$(date +%s)

    [ -z "$quiet" ] && echo -e "${DIM}Building call graph cache...${NC}"
    if ! timeout "$TLDR_WARM_TIMEOUT" tldr warm "$project_path" $lang_flag 2>&1; then
        [ -z "$quiet" ] && echo -e "${YELLOW}Warning: TLDR warm timed out or failed${NC}"
    fi

    # Build semantic index (for semantic search)
    [ -z "$quiet" ] && echo -e "${DIM}Building semantic index (this may take a while on first run)...${NC}"

    # Get configured embedding model
    local embedding_model=$(get_tldr_embedding_model)
    local model_flag="--model $embedding_model"
    [ -z "$quiet" ] && echo -e "${DIM}Using model: $embedding_model${NC}"

    # Try normal mode first, then CPU mode if MPS crashes
    local semantic_output
    semantic_output=$(timeout "$TLDR_WARM_TIMEOUT" tldr semantic index "$project_path" $lang_flag $model_flag 2>&1)
    local semantic_exit=$?

    # Check for MPS/Metal crash (exit code 134=SIGABRT, 139=SIGSEGV)
    if [ $semantic_exit -eq 134 ] || [ $semantic_exit -eq 139 ] || [[ "$semantic_output" == *"MPS"* ]] || [[ "$semantic_output" == *"Abort"* ]]; then
        [ -z "$quiet" ] && echo -e "${YELLOW}MPS crash detected, retrying with CPU mode + fallback model...${NC}"
        # Retry with CPU forced and smaller model
        semantic_output=$(PYTORCH_ENABLE_MPS_FALLBACK=1 MPS_DEVICE_ENABLE=0 timeout "$TLDR_WARM_TIMEOUT" tldr semantic index "$project_path" $lang_flag --model "$TLDR_FALLBACK_MODEL" 2>&1)
        semantic_exit=$?
    fi

    if [ $semantic_exit -ne 0 ]; then
        [ -z "$quiet" ] && echo -e "${YELLOW}Warning: Semantic index build timed out or failed${NC}"
        [ -z "$quiet" ] && echo -e "${DIM}Try: PYTORCH_ENABLE_MPS_FALLBACK=1 tldr semantic index \"$project_path\" $lang_flag $model_flag${NC}"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Count indexed symbols if possible
    local symbol_count=""
    if [ -d "$project_path/.tldr" ]; then
        symbol_count=$(find "$project_path/.tldr" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Check if semantic index exists
    local has_semantic=""
    if [ -f "$project_path/.tldr/cache/semantic/index.faiss" ]; then
        has_semantic=" + semantic"
    fi

    [ -z "$quiet" ] && echo -e "${GREEN}✓${NC} TLDR indexes ready${symbol_count:+ ($symbol_count files indexed)}${has_semantic} ${DIM}(${duration}s)${NC}"
    return 0
}

# Ensure .gitignore has common excludes (llm-tldr respects .gitignore)
ensure_gitignore_excludes() {
    local project_path="$1"
    local gitignore="$project_path/.gitignore"

    local required_patterns=(
        "node_modules"
        "dist"
        ".next"
        "build"
        "__pycache__"
        "*.pyc"
        "venv"
        ".venv"
        "target"
        "vendor"
    )

    # Create if doesn't exist
    if [ ! -f "$gitignore" ]; then
        printf '%s\n' "${required_patterns[@]}" > "$gitignore"
        return 0
    fi

    # Add missing patterns
    for pattern in "${required_patterns[@]}"; do
        if ! grep -qxF "$pattern" "$gitignore" 2>/dev/null; then
            echo "$pattern" >> "$gitignore"
        fi
    done
}

# Ensure .tldrignore exists with sensible defaults
ensure_tldr_ignore() {
    local project_path="$1"
    local ignore_file="$project_path/.tldrignore"

    # Default ignore patterns
    local default_patterns=(
        "node_modules"
        "dist"
        "build"
        ".next"
        ".nuxt"
        ".output"
        ".git"
        "__pycache__"
        "*.pyc"
        ".pytest_cache"
        "venv"
        ".venv"
        "env"
        ".env"
        "target"
        "vendor"
        "*.min.js"
        "*.bundle.js"
        "package-lock.json"
        "yarn.lock"
        "pnpm-lock.yaml"
        ".tldr"
    )

    # Create if doesn't exist
    if [ ! -f "$ignore_file" ]; then
        printf '%s\n' "${default_patterns[@]}" > "$ignore_file"
        return 0
    fi

    # Add custom patterns from config if specified
    local config_file="$project_path/.claude-workspace.json"
    if [ -f "$config_file" ]; then
        local custom_patterns
        custom_patterns=$(jq -r '.tldr.ignorePatterns // [] | .[]' "$config_file" 2>/dev/null)

        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            if ! grep -qxF "$pattern" "$ignore_file" 2>/dev/null; then
                echo "$pattern" >> "$ignore_file"
            fi
        done <<< "$custom_patterns"
    fi
}

#==============================================================================
# MCP Configuration
#==============================================================================

# Configure tldr MCP server for a project
# Usage: configure_tldr_mcp "/path/to/project"
configure_tldr_mcp() {
    local project_path="$1"
    local config_file="$project_path/.claude-workspace.json"

    # Check if auto-mcp is enabled (default true)
    local auto_mcp="true"
    if [ -f "$config_file" ]; then
        auto_mcp=$(jq -r '.tldr.autoMcp // true' "$config_file" 2>/dev/null)
    fi

    if [ "$auto_mcp" != "true" ]; then
        return 0
    fi

    # Check if tldr-mcp command exists
    local tldr_mcp_path
    tldr_mcp_path=$(which tldr-mcp 2>/dev/null)

    if [ -z "$tldr_mcp_path" ]; then
        echo -e "${YELLOW}Warning: tldr-mcp command not found${NC}"
        echo -e "${DIM}MCP server may not be available${NC}"
        return 1
    fi

    # Build MCP configuration for this project (use full path for reliability)
    local tldr_config
    tldr_config=$(cat << EOF
{
  "tldr": {
    "command": "$tldr_mcp_path",
    "args": ["--project", "$project_path"]
  }
}
EOF
)

    # Configure in project's .mcp.json (for general MCP support)
    local mcp_file="$project_path/.mcp.json"
    if [ -f "$mcp_file" ]; then
        local temp
        temp=$(mktemp)
        jq --argjson new_server "$tldr_config" \
           '.mcpServers = (.mcpServers // {}) + $new_server' \
           "$mcp_file" > "$temp" && mv "$temp" "$mcp_file"
    else
        echo "{\"mcpServers\": $tldr_config}" | jq '.' > "$mcp_file"
    fi

    # Configure in project's .claude/settings.json
    local claude_settings_dir="$project_path/.claude"
    local claude_settings_file="$claude_settings_dir/settings.json"

    mkdir -p "$claude_settings_dir"

    if [ -f "$claude_settings_file" ]; then
        # Merge with existing Claude settings
        local temp
        temp=$(mktemp)
        jq --argjson new_server "$tldr_config" \
           '.mcpServers = (.mcpServers // {}) + $new_server' \
           "$claude_settings_file" > "$temp" && mv "$temp" "$claude_settings_file"
    else
        # Create new Claude settings file
        echo "{\"mcpServers\": $tldr_config}" | jq '.' > "$claude_settings_file"
    fi

    # ALSO configure in GLOBAL ~/.claude/settings.json (Claude Code reads from here)
    local global_claude_dir="$HOME/.claude"
    local global_claude_settings="$global_claude_dir/settings.json"

    mkdir -p "$global_claude_dir"

    if [ -f "$global_claude_settings" ]; then
        # Merge with existing global settings
        local temp
        temp=$(mktemp)
        jq --argjson new_server "$tldr_config" \
           '.mcpServers = (.mcpServers // {}) + $new_server' \
           "$global_claude_settings" > "$temp" && mv "$temp" "$global_claude_settings"
    else
        # Create new global settings file
        echo "{\"mcpServers\": $tldr_config}" | jq '.' > "$global_claude_settings"
    fi

    echo -e "${GREEN}✓${NC} Configured TLDR MCP server (project + global)"
    return 0
}

# Remove tldr MCP configuration from a project
remove_tldr_mcp() {
    local project_path="$1"

    # Remove from .mcp.json
    local mcp_file="$project_path/.mcp.json"
    if [ -f "$mcp_file" ]; then
        local temp
        temp=$(mktemp)
        jq 'del(.mcpServers.tldr)' "$mcp_file" > "$temp" && mv "$temp" "$mcp_file"

        # Remove file if empty
        if [ "$(jq '.mcpServers | length' "$mcp_file" 2>/dev/null)" = "0" ]; then
            rm -f "$mcp_file"
        fi
    fi

    # Remove from .claude/settings.json
    local claude_settings_file="$project_path/.claude/settings.json"
    if [ -f "$claude_settings_file" ]; then
        local temp
        temp=$(mktemp)
        jq 'del(.mcpServers.tldr)' "$claude_settings_file" > "$temp" && mv "$temp" "$claude_settings_file"

        # Remove mcpServers key if empty (but keep other settings)
        if [ "$(jq '.mcpServers | length' "$claude_settings_file" 2>/dev/null)" = "0" ]; then
            temp=$(mktemp)
            jq 'del(.mcpServers)' "$claude_settings_file" > "$temp" && mv "$temp" "$claude_settings_file"
        fi
    fi

    echo -e "${GREEN}✓${NC} Removed TLDR MCP server configuration"
}

#==============================================================================
# CLAUDE.md Instructions
#==============================================================================

# Generate TLDR instructions for CLAUDE.md
generate_tldr_instructions() {
    cat << 'EOF'

## 🔍 Use TLDR MCP Tools for Code Exploration

**YOU HAVE TLDR MCP TOOLS** - Use them to explore code efficiently before reading raw files.

### Available MCP Tools (Most Reliable First)

| MCP Tool | When to Use | Reliability |
|----------|-------------|-------------|
| `tldr - search` | Find files/code by pattern (regex supported) | ✅ Always works |
| `tldr - extract` | Get structure of a specific file | ✅ Always works |
| `tldr - impact` | See what calls a function (reverse call graph) | ✅ Works if indexed |
| `tldr - calls` | See what a function calls | ✅ Works if indexed |
| `tldr - structure` | Get code structure overview | ✅ Always works |
| `tldr - semantic` | Semantic code search | ⚠️ May have limited coverage |

### ✅ REQUIRED Workflow

1. **Searching for code?** → \`tldr - search "pattern"\` FIRST, not \`Grep\`
2. **Need file structure?** → \`tldr - extract <file>\` to get classes/functions
3. **About to modify a function?** → \`tldr - impact <function>\` FIRST to see callers
4. **Want to see dependencies?** → \`tldr - calls <function>\` to see what it calls
5. **Semantic search** → Use \`tldr - semantic\` but note it may have gaps
6. **Only read raw files** when you need exact implementation details

### 🚫 DON'T DO THIS

- ❌ Don't read entire files to understand structure - use \`tldr - extract\`
- ❌ Don't grep for code patterns - use \`tldr - search\`
- ❌ Don't modify functions without checking callers - use \`tldr - impact\`

### Why TLDR?

- **95% fewer tokens** - structured summaries instead of raw code
- **Call graph analysis** - understands dependencies and relationships
- **Pre-indexed** - instant results, no scanning

**THE TLDR TOOLS ARE AVAILABLE. USE THEM PROACTIVELY.**

EOF
}

# Update project CLAUDE.md with TLDR instructions
update_project_claude_md() {
    local project_path="$1"
    local claude_md="$project_path/CLAUDE.md"

    # Generate instructions
    local instructions
    instructions=$(generate_tldr_instructions)

    if [ -f "$claude_md" ]; then
        # Check if already has TLDR section (check various markers)
        if grep -q "TLDR\|tldr_context\|tldr_semantic" "$claude_md"; then
            # Replace existing section - remove ALL TLDR sections first
            local temp
            temp=$(mktemp)
            awk '
                BEGIN { skip=0 }
                /## .*TLDR\|## .*Use TLDR/ { skip=1; next }
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
        # Create new file
        echo "# Project Instructions" > "$claude_md"
        echo "$instructions" >> "$claude_md"
    fi

    echo -e "${GREEN}✓${NC} Updated CLAUDE.md with TLDR instructions"
}

# Remove TLDR instructions from CLAUDE.md
remove_tldr_from_claude_md() {
    local project_path="$1"
    local claude_md="$project_path/CLAUDE.md"
    local marker="## TLDR Code Analysis"

    if [ -f "$claude_md" ] && grep -q "$marker" "$claude_md"; then
        local temp
        temp=$(mktemp)
        awk -v marker="$marker" '
            BEGIN { skip=0 }
            $0 ~ marker { skip=1; next }
            skip && /^## / { skip=0 }
            !skip { print }
        ' "$claude_md" > "$temp" && mv "$temp" "$claude_md"

        echo -e "${GREEN}✓${NC} Removed TLDR instructions from CLAUDE.md"
    fi
}

#==============================================================================
# Setup Functions
#==============================================================================

# Full TLDR setup for a project
# Usage: setup_tldr_for_project "/path/to/project"
setup_tldr_for_project() {
    local project_path="$1"

    echo -e "${BLUE}Setting up TLDR for project...${NC}"

    # Warm indexes
    if ! warm_tldr_indexes "$project_path"; then
        return 1
    fi

    # Configure MCP
    configure_tldr_mcp "$project_path"

    # Update CLAUDE.md
    update_project_claude_md "$project_path"

    echo -e "${GREEN}✓${NC} TLDR setup complete"
    return 0
}

# Remove TLDR from a project
teardown_tldr_for_project() {
    local project_path="$1"

    echo -e "${BLUE}Removing TLDR from project...${NC}"

    # Remove MCP config
    remove_tldr_mcp "$project_path"

    # Remove CLAUDE.md section
    remove_tldr_from_claude_md "$project_path"

    # Optionally remove indexes (ask user)
    if [ -d "$project_path/.tldr" ]; then
        echo -e "${DIM}Note: .tldr directory preserved. Remove manually if desired.${NC}"
    fi

    echo -e "${GREEN}✓${NC} TLDR removed from project"
    return 0
}

#==============================================================================
# Utility Functions
#==============================================================================

# Print TLDR status for a project
print_tldr_status() {
    local project_path="$1"

    echo -e "${BLUE}TLDR Status${NC}"
    echo ""

    # Installation status
    if detect_tldr_installation; then
        local version
        version=$(get_tldr_version)
        echo -e "  ${GREEN}✓${NC} Installed: $version"
    else
        echo -e "  ${RED}✗${NC} Not installed"
        echo -e "    ${DIM}Install with: pip install llm-tldr${NC}"
        return 1
    fi

    # Project status
    if is_tldr_enabled "$project_path"; then
        echo -e "  ${GREEN}●${NC} Enabled for this project"
    else
        echo -e "  ${DIM}○${NC} Not enabled for this project"
    fi

    # Index status
    if has_tldr_indexes "$project_path"; then
        local index_count
        index_count=$(find "$project_path/.tldr" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ${GREEN}●${NC} Indexes present ($index_count files)"
    else
        echo -e "  ${DIM}○${NC} No indexes (run 'tldr warm')"
    fi

    # MCP status
    if [ -f "$project_path/.mcp.json" ] && jq -e '.mcpServers.tldr' "$project_path/.mcp.json" &>/dev/null; then
        echo -e "  ${GREEN}●${NC} MCP server configured"
    else
        echo -e "  ${DIM}○${NC} MCP server not configured"
    fi

    echo ""
}
