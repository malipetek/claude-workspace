#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  TLDR SETUP - User-friendly llm-tldr setup and indexing
#══════════════════════════════════════════════════════════════════════════════
#
#  Handles the complete TLDR setup flow with clear progress feedback:
#  - Checks/installs llm-tldr
#  - Detects project language
#  - Builds indexes with progress
#  - Handles first-time model download
#  - Configures MCP for Claude
#
#  USAGE:
#    tldr-setup.sh [project_path]
#    tldr-setup.sh                  # Uses current directory
#
#══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$HOME/.claude-workspace/scripts"

# Parse arguments
PROJECT_PATH="${1:-.}"
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd)
PROJECT_NAME=$(basename "$PROJECT_PATH")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  TLDR Code Analysis Setup                                                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Project: ${CYAN}$PROJECT_NAME${NC}"
echo -e "Path: ${DIM}$PROJECT_PATH${NC}"
echo ""

#══════════════════════════════════════════════════════════════════════════════
# Step 1: Check/Install llm-tldr
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[1/6]${NC} Checking llm-tldr installation..."

if ! command -v tldr &>/dev/null; then
    echo -e "  ${YELLOW}!${NC} llm-tldr not found"
    echo -e "  ${DIM}Installing llm-tldr...${NC}"

    if command -v pip3 &>/dev/null; then
        pip3 install llm-tldr --quiet
    elif command -v pip &>/dev/null; then
        pip install llm-tldr --quiet
    else
        echo -e "  ${RED}✗${NC} pip not found. Please install Python and pip first."
        exit 1
    fi

    if command -v tldr &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} llm-tldr installed successfully"
    else
        echo -e "  ${RED}✗${NC} Installation failed. Try: pip install llm-tldr"
        exit 1
    fi
else
    # Verify it's llm-tldr, not man-pages tldr
    if tldr --help 2>&1 | grep -q "warm\|semantic"; then
        echo -e "  ${GREEN}✓${NC} llm-tldr is installed"
    else
        echo -e "  ${YELLOW}!${NC} Found 'tldr' but it's the man-pages version, not llm-tldr"
        echo -e "  ${DIM}Installing llm-tldr (will override)...${NC}"
        pip3 install llm-tldr --quiet 2>/dev/null || pip install llm-tldr --quiet
        echo -e "  ${GREEN}✓${NC} llm-tldr installed"
    fi
fi

#══════════════════════════════════════════════════════════════════════════════
# Step 2: Detect project language
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[2/6]${NC} Detecting project language..."

LANG_FLAG=""
LANG_NAME=""

# Helper: check for TypeScript files anywhere (excluding node_modules)
has_typescript_files() {
    find "$PROJECT_PATH" -name "*.ts" -o -name "*.tsx" 2>/dev/null | grep -v node_modules | head -1 | grep -q .
}

# Helper: check for tsconfig anywhere (monorepo support)
has_tsconfig() {
    find "$PROJECT_PATH" -name "tsconfig.json" -not -path "*/node_modules/*" 2>/dev/null | head -1 | grep -q .
}

if [ -f "$PROJECT_PATH/tsconfig.json" ]; then
    LANG_FLAG="--lang typescript"
    LANG_NAME="TypeScript"
elif has_tsconfig || has_typescript_files; then
    # Monorepo or project with TS files but no root tsconfig
    LANG_FLAG="--lang typescript"
    LANG_NAME="TypeScript (monorepo)"
elif [ -f "$PROJECT_PATH/package.json" ]; then
    LANG_FLAG="--lang javascript"
    LANG_NAME="JavaScript"
elif [ -f "$PROJECT_PATH/setup.py" ] || [ -f "$PROJECT_PATH/pyproject.toml" ] || [ -f "$PROJECT_PATH/requirements.txt" ]; then
    LANG_FLAG="--lang python"
    LANG_NAME="Python"
elif [ -f "$PROJECT_PATH/Cargo.toml" ]; then
    LANG_FLAG="--lang rust"
    LANG_NAME="Rust"
elif [ -f "$PROJECT_PATH/go.mod" ]; then
    LANG_FLAG="--lang go"
    LANG_NAME="Go"
elif [ -f "$PROJECT_PATH/pom.xml" ] || [ -f "$PROJECT_PATH/build.gradle" ]; then
    LANG_FLAG="--lang java"
    LANG_NAME="Java"
else
    LANG_FLAG="--lang all"
    LANG_NAME="Multi-language"
fi

echo -e "  ${GREEN}✓${NC} Detected: ${CYAN}$LANG_NAME${NC}"

#══════════════════════════════════════════════════════════════════════════════
# Step 3: Setup ignore files
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[3/6]${NC} Setting up ignore patterns..."

# Create .tldrignore if needed
TLDRIGNORE="$PROJECT_PATH/.tldrignore"
if [ ! -f "$TLDRIGNORE" ]; then
    cat > "$TLDRIGNORE" << 'EOF'
node_modules
dist
build
.next
.nuxt
.output
.git
__pycache__
*.pyc
.pytest_cache
venv
.venv
target
vendor
*.min.js
*.bundle.js
package-lock.json
yarn.lock
pnpm-lock.yaml
.tldr
EOF
    echo -e "  ${GREEN}✓${NC} Created .tldrignore"
else
    echo -e "  ${GREEN}✓${NC} .tldrignore exists"
fi

# Clean any corrupted indexes
if [ -d "$PROJECT_PATH/.tldr" ]; then
    rm -rf "$PROJECT_PATH/.tldr"
    echo -e "  ${DIM}Cleared old indexes${NC}"
fi

# Also clean nested .tldr directories
find "$PROJECT_PATH" -name ".tldr" -type d -not -path "*/node_modules/*" -exec rm -rf {} + 2>/dev/null || true

#══════════════════════════════════════════════════════════════════════════════
# Step 4: Build call graph index
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[4/6]${NC} Building call graph index..."
echo -e "  ${DIM}This analyzes function calls and relationships...${NC}"

cd "$PROJECT_PATH"
WARM_OUTPUT=$(tldr warm . $LANG_FLAG 2>&1)
WARM_EXIT=$?

# Parse the output for stats
FILES_COUNT=$(echo "$WARM_OUTPUT" | grep -oE '[0-9]+ files' | grep -oE '[0-9]+' | head -1 || echo "0")
EDGES_COUNT=$(echo "$WARM_OUTPUT" | grep -oE '[0-9]+ edges' | grep -oE '[0-9]+' | head -1 || echo "0")

if [ "$FILES_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Call graph built: ${FILES_COUNT} files, ${EDGES_COUNT} edges"
elif [ $WARM_EXIT -eq 0 ]; then
    echo -e "  ${YELLOW}!${NC} Call graph reports 0 files indexed"
    echo -e "  ${DIM}Possible causes:${NC}"
    echo -e "  ${DIM}- Wrong language detected (try: tldr warm . --lang all)${NC}"
    echo -e "  ${DIM}- All files ignored by .gitignore or .tldrignore${NC}"
    echo -e "  ${DIM}- No supported code files found${NC}"

    # Try to help diagnose
    SRC_FILES=$(find . -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null | grep -v node_modules | grep -v dist | head -5)
    if [ -n "$SRC_FILES" ]; then
        echo -e "  ${DIM}Found source files:${NC}"
        echo "$SRC_FILES" | while read f; do echo -e "    ${DIM}$f${NC}"; done
        echo -e "  ${DIM}Try: tldr warm . --lang all${NC}"
    fi
else
    echo -e "  ${RED}✗${NC} Call graph build failed"
    echo -e "  ${DIM}$WARM_OUTPUT${NC}"
fi

#══════════════════════════════════════════════════════════════════════════════
# Step 5: Select embedding model
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[5/6]${NC} Selecting embedding model..."

# Define available models
declare -A MODELS
MODELS["1"]="BAAI/bge-base-en-v1.5|440MB|Best balance of size/quality (Recommended)"
MODELS["2"]="BAAI/bge-large-en-v1.5|1.3GB|Highest quality, slower"
MODELS["3"]="sentence-transformers/all-mpnet-base-v2|420MB|Good general-purpose"
MODELS["4"]="sentence-transformers/all-MiniLM-L6-v2|80MB|Fast, lower quality"

# Check for saved preference
SETTINGS_FILE="$HOME/.claude-workspace/settings.json"
SAVED_MODEL=""
if [ -f "$SETTINGS_FILE" ]; then
    SAVED_MODEL=$(jq -r '.tldr.embeddingModel // empty' "$SETTINGS_FILE" 2>/dev/null)
fi

# Check which models are already downloaded
echo ""
echo -e "  ${BOLD}Available embedding models:${NC}"
echo ""

for key in 1 2 3 4; do
    IFS='|' read -r model_name model_size model_desc <<< "${MODELS[$key]}"

    # Check if model is downloaded
    model_dir_name=$(echo "$model_name" | tr '/' '--')
    model_path="$HOME/.cache/huggingface/hub/models--$model_dir_name"

    if [ -d "$model_path" ]; then
        downloaded="${GREEN}[downloaded]${NC}"
    else
        downloaded="${DIM}[not downloaded]${NC}"
    fi

    # Mark default
    if [ "$model_name" = "$SAVED_MODEL" ]; then
        marker="${CYAN}*${NC}"
    elif [ "$key" = "1" ] && [ -z "$SAVED_MODEL" ]; then
        marker="${CYAN}*${NC}"
    else
        marker=" "
    fi

    echo -e "  $marker ${BOLD}$key)${NC} $model_name"
    echo -e "       ${DIM}$model_size - $model_desc${NC} $downloaded"
done

echo ""
echo -e "  ${DIM}* = current selection${NC}"
echo ""

# Prompt for selection
read -p "  Select model [1-4, Enter for default]: " MODEL_CHOICE
MODEL_CHOICE=${MODEL_CHOICE:-1}

# Validate choice
if [[ ! "$MODEL_CHOICE" =~ ^[1-4]$ ]]; then
    MODEL_CHOICE="1"
fi

IFS='|' read -r SELECTED_MODEL MODEL_SIZE MODEL_DESC <<< "${MODELS[$MODEL_CHOICE]}"
echo -e "  ${GREEN}✓${NC} Selected: ${CYAN}$SELECTED_MODEL${NC} ($MODEL_SIZE)"

# Save preference
if [ -f "$SETTINGS_FILE" ]; then
    jq --arg model "$SELECTED_MODEL" '.tldr.embeddingModel = $model' "$SETTINGS_FILE" > /tmp/settings.json && mv /tmp/settings.json "$SETTINGS_FILE"
elif [ -d "$HOME/.claude-workspace" ]; then
    echo "{\"tldr\": {\"embeddingModel\": \"$SELECTED_MODEL\"}}" | jq '.' > "$SETTINGS_FILE"
fi

# Build the model flag
MODEL_FLAG="--model $SELECTED_MODEL"

# Check if model needs download
model_dir_name=$(echo "$SELECTED_MODEL" | tr '/' '--')
MODEL_PATH="$HOME/.cache/huggingface/hub/models--$model_dir_name"

#══════════════════════════════════════════════════════════════════════════════
# Step 6: Build semantic index
#══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}[6/6]${NC} Building semantic search index..."

if [ ! -d "$MODEL_PATH" ]; then
    echo -e "  ${YELLOW}!${NC} First-time setup: Downloading embedding model ($MODEL_SIZE)"
    echo -e "  ${DIM}This only happens once and enables semantic code search...${NC}"
    echo ""
fi

# Spinner function
spin() {
    local pid=$1
    local delay=0.2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r  ${CYAN}%c${NC} Indexing... (%ds)" "$spinstr" "$elapsed"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        elapsed=$((elapsed + 1))
        # Timeout after 5 minutes
        if [ $elapsed -gt 300 ]; then
            echo ""
            echo -e "  ${YELLOW}!${NC} Indexing taking too long, stopping..."
            kill $pid 2>/dev/null
            break
        fi
    done
    printf "\r                                    \r"
}

# Run semantic index in background with spinner
echo -e "  ${DIM}This may take 1-2 minutes...${NC}"

# CPU fallback model (smaller, more stable)
CPU_FALLBACK_MODEL="sentence-transformers/all-MiniLM-L6-v2"

# Function to run semantic indexing with retry logic
run_semantic_index() {
    local use_cpu="$1"
    local env_prefix=""
    local model_to_use="$MODEL_FLAG"

    if [ "$use_cpu" = "true" ]; then
        # Force CPU mode to avoid MPS crashes on Apple Silicon
        # Also use smaller model for faster CPU processing
        env_prefix="PYTORCH_ENABLE_MPS_FALLBACK=1 MPS_DEVICE_ENABLE=0"
        model_to_use="--model $CPU_FALLBACK_MODEL"
        echo -e "  ${DIM}Retrying with CPU mode + smaller model...${NC}"
    fi

    # Run with timeout and spinner
    env $env_prefix tldr semantic index . $LANG_FLAG $model_to_use > /tmp/tldr_semantic_$$.log 2>&1 &
    local pid=$!

    spin $pid
    wait $pid 2>/dev/null
    return $?
}

# First attempt - normal mode
run_semantic_index "false"
SEMANTIC_EXIT=$?

# Check for MPS crash and retry with CPU if needed
if [ -f /tmp/tldr_semantic_$$.log ]; then
    OUTPUT=$(cat /tmp/tldr_semantic_$$.log)

    # Detect MPS/Metal crash
    if [[ "$OUTPUT" == *"MPS"* ]] || [[ "$OUTPUT" == *"Metal"* ]] || [[ "$OUTPUT" == *"SIGABRT"* ]] || [[ "$OUTPUT" == *"Abort trap"* ]] || [ $SEMANTIC_EXIT -eq 134 ] || [ $SEMANTIC_EXIT -eq 139 ]; then
        echo -e "  ${YELLOW}!${NC} MPS crash detected, retrying with CPU..."
        rm -f /tmp/tldr_semantic_$$.log

        # Retry with CPU forced
        run_semantic_index "true"
        SEMANTIC_EXIT=$?
    fi
fi

# Show output
if [ -f /tmp/tldr_semantic_$$.log ]; then
    OUTPUT=$(cat /tmp/tldr_semantic_$$.log)
    rm -f /tmp/tldr_semantic_$$.log

    if [[ "$OUTPUT" == *"Indexed"* ]]; then
        INDEXED=$(echo "$OUTPUT" | grep -oE 'Indexed [0-9]+ code units' || echo "$OUTPUT")
        echo -e "  ${GREEN}✓${NC} $INDEXED"
    elif [[ "$OUTPUT" == *"error"* ]] || [[ "$OUTPUT" == *"Error"* ]] || [[ "$OUTPUT" == *"MPS"* ]] || [[ "$OUTPUT" == *"Abort"* ]]; then
        echo -e "  ${RED}!${NC} Error during indexing"
        echo -e "  ${DIM}$OUTPUT${NC}"
    elif [ -n "$OUTPUT" ]; then
        echo -e "  ${DIM}$OUTPUT${NC}"
    fi
fi

# Verify semantic index was created and is valid
SEMANTIC_OK=false
if [ -f "$PROJECT_PATH/.tldr/cache/semantic/index.faiss" ]; then
    # Check if semantic index has reasonable coverage
    CALL_GRAPH_FILES=$(jq '[.edges[].from_file] | unique | length' "$PROJECT_PATH/.tldr/cache/call_graph.json" 2>/dev/null || echo "0")
    SEMANTIC_FILES=$(jq 'if type == "array" then [.[].file] | unique | length else [.units[].file] | unique | length end' "$PROJECT_PATH/.tldr/cache/semantic/metadata.json" 2>/dev/null || echo "0")

    if [ "$SEMANTIC_FILES" -gt 0 ]; then
        COVERAGE=$((SEMANTIC_FILES * 100 / (CALL_GRAPH_FILES + 1)))
        if [ "$COVERAGE" -ge 50 ]; then
            echo -e "  ${GREEN}✓${NC} Semantic index ready ($SEMANTIC_FILES/$CALL_GRAPH_FILES files, ${COVERAGE}% coverage)"
            SEMANTIC_OK=true
        else
            echo -e "  ${YELLOW}!${NC} Semantic index incomplete ($SEMANTIC_FILES/$CALL_GRAPH_FILES files, ${COVERAGE}% coverage)"
            echo -e "  ${DIM}This is a known llm-tldr bug. Other tools still work.${NC}"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Semantic index empty"
    fi
else
    echo -e "  ${YELLOW}!${NC} Semantic index not created"
fi

#══════════════════════════════════════════════════════════════════════════════
# Configure MCP for Claude
#══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}Configuring Claude MCP...${NC}"

TLDR_MCP_PATH=$(which tldr-mcp 2>/dev/null || echo "")

if [ -n "$TLDR_MCP_PATH" ]; then
    # Configure in global Claude settings
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"

    if [ -f "$CLAUDE_SETTINGS" ]; then
        # Update existing
        jq --arg cmd "$TLDR_MCP_PATH" \
           '.mcpServers.tldr = {"command": $cmd, "args": ["--project", "."]}' \
           "$CLAUDE_SETTINGS" > /tmp/claude_settings.json 2>/dev/null && \
           mv /tmp/claude_settings.json "$CLAUDE_SETTINGS"
    else
        # Create new
        echo "{\"mcpServers\": {\"tldr\": {\"command\": \"$TLDR_MCP_PATH\", \"args\": [\"--project\", \".\"]}}}" | jq '.' > "$CLAUDE_SETTINGS"
    fi

    echo -e "  ${GREEN}✓${NC} MCP configured in ~/.claude/settings.json"
else
    echo -e "  ${YELLOW}!${NC} tldr-mcp not found (MCP features won't work)"
fi

#══════════════════════════════════════════════════════════════════════════════
# Verify Tools Work
#══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}Verifying tools...${NC}"

TOOLS_STATUS=""

# Test search
if tldr search "function" --path . >/dev/null 2>&1; then
    TOOLS_STATUS="${TOOLS_STATUS}${GREEN}✓${NC} search  "
else
    TOOLS_STATUS="${TOOLS_STATUS}${RED}✗${NC} search  "
fi

# Test structure
if tldr structure --path . >/dev/null 2>&1; then
    TOOLS_STATUS="${TOOLS_STATUS}${GREEN}✓${NC} structure  "
else
    TOOLS_STATUS="${TOOLS_STATUS}${RED}✗${NC} structure  "
fi

# Test calls (needs call graph)
if [ -f "$PROJECT_PATH/.tldr/cache/call_graph.json" ]; then
    TOOLS_STATUS="${TOOLS_STATUS}${GREEN}✓${NC} calls/impact  "
else
    TOOLS_STATUS="${TOOLS_STATUS}${RED}✗${NC} calls/impact  "
fi

# Test semantic
if [ "$SEMANTIC_OK" = true ]; then
    TOOLS_STATUS="${TOOLS_STATUS}${GREEN}✓${NC} semantic"
else
    TOOLS_STATUS="${TOOLS_STATUS}${YELLOW}~${NC} semantic"
fi

echo -e "  $TOOLS_STATUS"

#══════════════════════════════════════════════════════════════════════════════
# Done
#══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup Complete!                                                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "TLDR is now ready for ${CYAN}$PROJECT_NAME${NC}"
echo ""
echo -e "${BOLD}Working tools:${NC}"
echo -e "  ${CYAN}tldr search \"pattern\"${NC}  - Find files by pattern"
echo -e "  ${CYAN}tldr structure${NC}         - See code structure overview"
echo -e "  ${CYAN}tldr extract <file>${NC}    - Extract file info"
echo -e "  ${CYAN}tldr calls <fn>${NC}        - See what a function calls"
echo -e "  ${CYAN}tldr impact <fn>${NC}       - See what calls a function"

if [ "$SEMANTIC_OK" = true ]; then
    echo -e "  ${CYAN}tldr semantic search \"query\"${NC} - Semantic code search"
else
    echo ""
    echo -e "${YELLOW}Note:${NC} Semantic search has limited coverage due to an llm-tldr bug."
    echo -e "      Use ${CYAN}tldr search${NC} for pattern-based search instead."
fi

echo ""
echo -e "${BOLD}In Claude Code:${NC}"
echo -e "  Restart Claude to load MCP, then use: ${CYAN}tldr - search${NC}, ${CYAN}tldr - extract${NC}, ${CYAN}tldr - impact${NC}"
echo ""
