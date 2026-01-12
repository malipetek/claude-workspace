#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE INSTALLER
#══════════════════════════════════════════════════════════════════════════════
#
#  Installs claude-workspace - a workspace manager for Claude Code
#
#  USAGE:
#    curl -fsSL https://raw.githubusercontent.com/malipetek/claude-workspace/main/install.sh | bash
#
#    Or clone and run:
#    git clone https://github.com/malipetek/claude-workspace.git
#    cd claude-workspace && ./install.sh
#
#══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="$HOME/.claude-workspace"
BIN_DIR="$HOME/.local/bin"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}CLAUDE WORKSPACE INSTALLER${NC}                                                 ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Workspace manager for Claude Code with Ghostty integration               ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 - $2"
        return 1
    fi
}

# Check bash version (need 4+ for mapfile)
check_bash_version() {
    local bash_path=$(which bash)
    local bash_version=$("$bash_path" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major_version=$(echo "$bash_version" | cut -d. -f1)

    if [ "$major_version" -ge 4 ] 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} bash $bash_version"
        return 0
    else
        echo -e "  ${YELLOW}!${NC} bash $bash_version (version 4+ recommended)"
        echo -e "    ${DIM}Some interactive features may not work${NC}"
        echo -e "    ${DIM}Install newer bash: brew install bash${NC}"
        return 1
    fi
}

MISSING_DEPS=0

check_bash_version || true
check_command "jq" "Install with: brew install jq" || MISSING_DEPS=1
check_command "claude" "Install Claude Code from: https://claude.ai/code" || MISSING_DEPS=1

# Optional dependencies
echo ""
echo -e "${BLUE}Optional dependencies:${NC}"
check_command "ghostty" "For split-pane workspaces: https://ghostty.org" || true
check_command "gemini" "For AI delegation: Gemini CLI" || true

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Warning: Some required dependencies are missing.${NC}"
    echo -e "Please install them before using claude-workspace."
    echo ""
    read -p "Continue installation anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Determine source directory (if running from cloned repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/scripts/workspace.sh" ]; then
    SOURCE_DIR="$SCRIPT_DIR"
    echo ""
    echo -e "${BLUE}Installing from local directory: $SOURCE_DIR${NC}"
else
    # Download from GitHub
    echo ""
    echo -e "${BLUE}Downloading claude-workspace...${NC}"
    SOURCE_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/malipetek/claude-workspace.git "$SOURCE_DIR" 2>/dev/null || {
        echo -e "${RED}Failed to clone repository${NC}"
        exit 1
    }
fi

# Create installation directory
echo ""
echo -e "${BLUE}Installing to $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR"/{scripts,scripts/lib,templates,logs,dev-logs,status,dev-markers}

# Copy scripts
cp "$SOURCE_DIR"/scripts/*.sh "$INSTALL_DIR/scripts/" 2>/dev/null || true
cp "$SOURCE_DIR"/scripts/*.applescript "$INSTALL_DIR/scripts/" 2>/dev/null || true
cp "$SOURCE_DIR"/scripts/ai-project "$INSTALL_DIR/scripts/" 2>/dev/null || true
cp "$SOURCE_DIR"/scripts/lib/*.sh "$INSTALL_DIR/scripts/lib/" 2>/dev/null || true
cp "$SOURCE_DIR"/templates/*.json "$INSTALL_DIR/templates/" 2>/dev/null || true
cp "$SOURCE_DIR"/aliases.sh "$INSTALL_DIR/" 2>/dev/null || true

# Make scripts executable
chmod +x "$INSTALL_DIR"/scripts/*
chmod +x "$INSTALL_DIR"/scripts/lib/* 2>/dev/null || true

# Create registry.json if it doesn't exist
if [ ! -f "$INSTALL_DIR/registry.json" ]; then
    cat > "$INSTALL_DIR/registry.json" << 'EOF'
{
  "projects": {},
  "stats": {
    "total_tasks_delegated": 0,
    "gemini_tasks": 0,
    "zai_tasks": 0
  },
  "metadata": {
    "created": "",
    "last_updated": ""
  }
}
EOF
    # Set created date
    if command -v jq &> /dev/null; then
        TEMP=$(mktemp)
        jq ".metadata.created = \"$(date +%Y-%m-%d)\" | .metadata.last_updated = \"$(date +%Y-%m-%d)\"" "$INSTALL_DIR/registry.json" > "$TEMP"
        mv "$TEMP" "$INSTALL_DIR/registry.json"
    fi
fi

# Create bin directory and symlink
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/scripts/ai-project" "$BIN_DIR/claude-workspace"
ln -sf "$INSTALL_DIR/scripts/workspace.sh" "$BIN_DIR/cw-open"
ln -sf "$INSTALL_DIR/scripts/dev-logs.sh" "$BIN_DIR/cw-logs"
ln -sf "$INSTALL_DIR/scripts/workspace-cleanup.sh" "$BIN_DIR/cw-cleanup"

# Create CLAUDE.md for Claude Code integration
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo ""
    echo -e "${YELLOW}Existing ~/.claude/CLAUDE.md found.${NC}"
    read -p "Append claude-workspace instructions? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "" >> "$CLAUDE_DIR/CLAUDE.md"
        echo "# Claude Workspace Integration" >> "$CLAUDE_DIR/CLAUDE.md"
        cat "$SOURCE_DIR/docs/CLAUDE_INSTRUCTIONS.md" >> "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Instructions appended to CLAUDE.md"
    fi
else
    cp "$SOURCE_DIR/docs/CLAUDE_INSTRUCTIONS.md" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Created ~/.claude/CLAUDE.md"
fi

# Check if PATH includes bin directory
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}Note: $BIN_DIR is not in your PATH${NC}"
    echo ""
    echo "Add this to your ~/.zshrc or ~/.bashrc:"
    echo ""
    echo -e "  ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo -e "  ${CYAN}source ~/.claude-workspace/aliases.sh${NC}"
    echo ""
fi

# Cleanup temp directory if used
if [ "$SOURCE_DIR" != "$SCRIPT_DIR" ] && [ -d "$SOURCE_DIR" ]; then
    rm -rf "$SOURCE_DIR"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${GREEN}✓ Installation complete!${NC}                                                   ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Installed to: ${CYAN}$INSTALL_DIR${NC}"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo ""
echo -e "  1. Run the setup wizard:"
echo -e "     ${CYAN}claude-workspace setup${NC}"
echo ""
echo -e "  2. Or add a project manually:"
echo -e "     ${CYAN}claude-workspace add /path/to/project${NC}"
echo ""
echo -e "  3. Launch a workspace:"
echo -e "     ${CYAN}claude-workspace${NC}"
echo ""
echo -e "${BLUE}Commands:${NC}"
echo -e "  ${CYAN}claude-workspace${NC}          Interactive project switcher"
echo -e "  ${CYAN}claude-workspace setup${NC}    Run setup wizard"
echo -e "  ${CYAN}claude-workspace add${NC}      Add a project"
echo -e "  ${CYAN}claude-workspace --help${NC}   Show help"
echo ""
echo -e "${BLUE}Aliases (add to shell config):${NC}"
echo -e "  ${CYAN}source ~/.claude-workspace/aliases.sh${NC}"
echo ""
