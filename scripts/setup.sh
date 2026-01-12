#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE SETUP WIZARD
#══════════════════════════════════════════════════════════════════════════════
#
#  Interactive setup wizard to:
#  - Find and register projects
#  - Create .ai-workspace.json configs
#  - Configure dev processes
#
#  USAGE:
#    setup.sh
#    setup.sh /path/to/project    # Setup specific project
#
#══════════════════════════════════════════════════════════════════════════════

INSTALL_DIR="$HOME/.claude-workspace"
REGISTRY="$INSTALL_DIR/registry.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Ensure registry exists
mkdir -p "$INSTALL_DIR"
if [ ! -f "$REGISTRY" ]; then
    echo '{"projects":{}}' > "$REGISTRY"
fi

show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}CLAUDE WORKSPACE SETUP WIZARD${NC}                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to detect package.json scripts
detect_npm_scripts() {
    local project_path="$1"
    local pkg_file="$project_path/package.json"

    if [ -f "$pkg_file" ]; then
        local scripts=$(jq -r '.scripts | keys[]' "$pkg_file" 2>/dev/null | grep -E "^(dev|start|watch|serve)$" | head -5)
        echo "$scripts"
    fi
}

# Function to detect project type and suggest processes
detect_project_type() {
    local project_path="$1"

    echo -e "${BLUE}Analyzing project structure...${NC}"
    echo ""

    local suggestions=()

    # Check for monorepo patterns
    if [ -d "$project_path/packages" ] || [ -d "$project_path/apps" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Monorepo structure"

        for dir in "$project_path"/{packages,apps}/*; do
            if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
                local name=$(basename "$dir")
                local has_dev=$(jq -r '.scripts.dev // empty' "$dir/package.json" 2>/dev/null)
                if [ -n "$has_dev" ]; then
                    suggestions+=("$name:pnpm dev:$dir")
                fi
            fi
        done
    fi

    # Check for common frameworks
    if [ -f "$project_path/next.config.js" ] || [ -f "$project_path/next.config.mjs" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Next.js"
        suggestions+=("nextjs:pnpm dev:.")
    fi

    if [ -f "$project_path/vite.config.js" ] || [ -f "$project_path/vite.config.ts" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Vite"
        suggestions+=("vite:pnpm dev:.")
    fi

    if [ -f "$project_path/nest-cli.json" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: NestJS"
        suggestions+=("nest:pnpm start:dev:.")
    fi

    if [ -f "$project_path/Cargo.toml" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Rust/Cargo"
        suggestions+=("rust:cargo watch -x run:.")
    fi

    if [ -f "$project_path/go.mod" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Go"
        suggestions+=("go:go run .:.")
    fi

    if [ -f "$project_path/convex.json" ] || [ -d "$project_path/convex" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Convex"
        suggestions+=("convex:npx convex dev:.")
    fi

    if [ -f "$project_path/prisma/schema.prisma" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Prisma"
    fi

    if [ -f "$project_path/docker-compose.yml" ] || [ -f "$project_path/docker-compose.yaml" ]; then
        echo -e "  ${GREEN}✓${NC} Detected: Docker Compose"
    fi

    printf '%s\n' "${suggestions[@]}"
}

# Function to create workspace config interactively
create_workspace_config() {
    local project_path="$1"
    local config_file="$project_path/.ai-workspace.json"

    show_header
    echo -e "${BOLD}Setting up workspace for:${NC} $(basename "$project_path")"
    echo -e "${BLUE}Path:${NC} $project_path"
    echo ""

    local suggestions=$(detect_project_type "$project_path")

    echo ""

    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}Existing .ai-workspace.json found.${NC}"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    local processes=()

    if [ -n "$suggestions" ]; then
        echo ""
        echo -e "${BLUE}Suggested dev processes:${NC}"
        echo ""

        local i=1
        while IFS= read -r suggestion; do
            [ -z "$suggestion" ] && continue
            local name=$(echo "$suggestion" | cut -d: -f1)
            local cmd=$(echo "$suggestion" | cut -d: -f2)
            local cwd=$(echo "$suggestion" | cut -d: -f3)
            echo -e "  ${CYAN}[$i]${NC} $name: $cmd (in $cwd)"
            ((i++))
        done <<< "$suggestions"

        echo ""
        read -p "Use suggested processes? [Y/n] " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            while IFS= read -r suggestion; do
                [ -z "$suggestion" ] && continue
                local name=$(echo "$suggestion" | cut -d: -f1)
                local cmd=$(echo "$suggestion" | cut -d: -f2)
                local cwd=$(echo "$suggestion" | cut -d: -f3)
                processes+=("{\"name\": \"$name\", \"command\": \"$cmd\", \"cwd\": \"$cwd\"}")
            done <<< "$suggestions"
        fi
    fi

    echo ""
    echo -e "${BLUE}Add custom dev processes${NC} (leave empty to finish):"
    echo ""

    while true; do
        read -p "Process name (e.g., 'frontend'): " proc_name
        [ -z "$proc_name" ] && break

        read -p "Command (e.g., 'pnpm dev'): " proc_cmd
        [ -z "$proc_cmd" ] && continue

        read -p "Working directory (relative, e.g., './frontend' or '.'): " proc_cwd
        proc_cwd=${proc_cwd:-.}

        processes+=("{\"name\": \"$proc_name\", \"command\": \"$proc_cmd\", \"cwd\": \"$proc_cwd\"}")
        echo -e "  ${GREEN}✓${NC} Added: $proc_name"
        echo ""
    done

    local processes_json=$(printf '%s\n' "${processes[@]}" | paste -sd ',' -)

    cat > "$config_file" << EOF
{
  "processes": [
    ${processes_json}
  ]
}
EOF

    if command -v jq &> /dev/null; then
        local temp=$(mktemp)
        jq '.' "$config_file" > "$temp" 2>/dev/null && mv "$temp" "$config_file"
    fi

    echo ""
    echo -e "${GREEN}✓${NC} Created $config_file"
    echo ""
    echo -e "${BLUE}Contents:${NC}"
    cat "$config_file"
}

# Function to add project to registry
add_project_to_registry() {
    local project_path="$1"
    local project_name=$(basename "$project_path")

    read -p "Project name [$project_name]: " custom_name
    project_name=${custom_name:-$project_name}

    read -p "Description (optional): " description

    local temp=$(mktemp)
    jq ".projects[\"$project_name\"] = {\"path\": \"$project_path\", \"description\": \"$description\", \"status\": \"active\"}" "$REGISTRY" > "$temp"
    mv "$temp" "$REGISTRY"

    echo -e "${GREEN}✓${NC} Added '$project_name' to registry"
}

# Interactive multi-select function
# Usage: interactive_select "Title" array[@] selected[@]
# Returns selected indices in SELECTED_INDICES array
interactive_multiselect() {
    local title="$1"
    shift
    local -a items=("$@")
    local total=${#items[@]}

    # Initialize selection state (all unselected)
    local -a selected=()
    for ((i=0; i<total; i++)); do
        selected[$i]=0
    done

    local current=0

    # Hide cursor
    tput civis

    # Cleanup on exit
    cleanup() {
        tput cnorm
        tput sgr0
    }
    trap cleanup EXIT

    draw_multiselect() {
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}$title${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Space: Toggle   Enter: Confirm   a: All   n: None   q: Cancel${NC}"
        echo ""

        for ((i=0; i<total; i++)); do
            local item="${items[$i]}"
            local name=$(basename "$item")
            local checkbox="[ ]"
            local has_workspace=""

            [ -f "$item/.ai-workspace.json" ] && has_workspace=" ${CYAN}[configured]${NC}"

            if [ "${selected[$i]}" -eq 1 ]; then
                checkbox="${GREEN}[✓]${NC}"
            fi

            if [ $i -eq $current ]; then
                echo -e "  ${BOLD}▶ $checkbox $name$has_workspace${NC}"
                echo -e "    ${DIM}$item${NC}"
            else
                echo -e "    $checkbox $name$has_workspace"
            fi
        done

        # Count selected
        local count=0
        for s in "${selected[@]}"; do
            [ "$s" -eq 1 ] && ((count++))
        done

        echo ""
        echo -e "  ${BLUE}Selected: $count / $total${NC}"
    }

    draw_multiselect

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                SELECTED_INDICES=()
                return 1
                ;;
            a|A)  # Select all
                for ((i=0; i<total; i++)); do
                    selected[$i]=1
                done
                draw_multiselect
                ;;
            n|N)  # Select none
                for ((i=0; i<total; i++)); do
                    selected[$i]=0
                done
                draw_multiselect
                ;;
            " ")  # Space - toggle selection
                if [ "${selected[$current]}" -eq 1 ]; then
                    selected[$current]=0
                else
                    selected[$current]=1
                fi
                draw_multiselect
                ;;
            "")  # Enter - confirm
                break
                ;;
            $'\x1b')  # Escape sequence (arrow keys)
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # Up arrow
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        draw_multiselect
                        ;;
                    '[B')  # Down arrow
                        ((current++))
                        [ $current -ge $total ] && current=0
                        draw_multiselect
                        ;;
                esac
                ;;
        esac
    done

    # Build result array
    SELECTED_INDICES=()
    for ((i=0; i<total; i++)); do
        if [ "${selected[$i]}" -eq 1 ]; then
            SELECTED_INDICES+=($i)
        fi
    done

    return 0
}

# Interactive folder navigator
# Usage: interactive_folder_select "Title" [start_path]
# Returns selected path in SELECTED_PATH variable
interactive_folder_select() {
    local title="$1"
    local current_dir="${2:-$HOME}"

    # Normalize path
    current_dir="${current_dir/#\~/$HOME}"
    [ ! -d "$current_dir" ] && current_dir="$HOME"

    local current=0

    # Hide cursor
    tput civis

    # Cleanup on exit
    local cleanup_set=false
    if [ -z "$(trap -p EXIT)" ]; then
        cleanup() {
            tput cnorm
            tput sgr0
        }
        trap cleanup EXIT
        cleanup_set=true
    fi

    get_dirs() {
        local dir="$1"
        local -a result=()

        # Add parent directory option if not at root
        if [ "$dir" != "/" ]; then
            result+=("..")
        fi

        # Get subdirectories (visible ones only, sorted)
        while IFS= read -r d; do
            [ -n "$d" ] && result+=("$(basename "$d")")
        done < <(find "$dir" -maxdepth 1 -type d ! -name ".*" ! -path "$dir" 2>/dev/null | sort)

        printf '%s\n' "${result[@]}"
    }

    draw_folder_menu() {
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}$title${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${DIM}↑/↓: Navigate   Enter: Open folder   s: Select this folder   q: Cancel${NC}"
        echo ""
        echo -e "  ${BLUE}Current:${NC} ${BOLD}$current_dir${NC}"
        echo ""

        # Get directories
        mapfile -t dirs < <(get_dirs "$current_dir")
        local total=${#dirs[@]}

        if [ $total -eq 0 ]; then
            echo -e "  ${DIM}(empty directory)${NC}"
        else
            # Calculate visible range (show max 15 items)
            local visible=15
            local start=0
            local end=$total

            if [ $total -gt $visible ]; then
                start=$((current - visible/2))
                [ $start -lt 0 ] && start=0
                end=$((start + visible))
                [ $end -gt $total ] && end=$total && start=$((end - visible))
            fi

            [ $start -gt 0 ] && echo -e "  ${DIM}  ↑ more above${NC}"

            for ((i=start; i<end; i++)); do
                local name="${dirs[$i]}"
                local icon="📁"
                [ "$name" = ".." ] && icon="📂"

                if [ $i -eq $current ]; then
                    echo -e "  ${BOLD}▶ $icon $name${NC}"
                else
                    echo -e "    $icon $name"
                fi
            done

            [ $end -lt $total ] && echo -e "  ${DIM}  ↓ more below${NC}"
        fi

        echo ""
        echo -e "  ${DIM}Press 's' to select current folder, 'h' to toggle hidden${NC}"
    }

    local show_hidden=false

    draw_folder_menu

    while true; do
        read -rsn1 key

        # Get current dirs for navigation
        mapfile -t dirs < <(get_dirs "$current_dir")
        local total=${#dirs[@]}

        case "$key" in
            q|Q)
                SELECTED_PATH=""
                return 1
                ;;
            s|S)  # Select current folder
                SELECTED_PATH="$current_dir"
                clear
                return 0
                ;;
            h|H)  # Toggle hidden files (future enhancement)
                show_hidden=!$show_hidden
                current=0
                draw_folder_menu
                ;;
            "")  # Enter - open selected folder
                if [ $total -gt 0 ]; then
                    local selected_name="${dirs[$current]}"
                    if [ "$selected_name" = ".." ]; then
                        current_dir=$(dirname "$current_dir")
                    else
                        local new_dir="$current_dir/$selected_name"
                        if [ -d "$new_dir" ]; then
                            current_dir="$new_dir"
                        fi
                    fi
                    current=0
                    draw_folder_menu
                fi
                ;;
            $'\x1b')  # Escape sequence (arrow keys)
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # Up arrow
                        ((current--))
                        [ $current -lt 0 ] && current=$((total > 0 ? total - 1 : 0))
                        draw_folder_menu
                        ;;
                    '[B')  # Down arrow
                        ((current++))
                        [ $current -ge $total ] && current=0
                        draw_folder_menu
                        ;;
                    '[D')  # Left arrow - go to parent
                        if [ "$current_dir" != "/" ]; then
                            current_dir=$(dirname "$current_dir")
                            current=0
                            draw_folder_menu
                        fi
                        ;;
                    '[C')  # Right arrow - enter folder
                        if [ $total -gt 0 ]; then
                            local selected_name="${dirs[$current]}"
                            if [ "$selected_name" = ".." ]; then
                                current_dir=$(dirname "$current_dir")
                            else
                                local new_dir="$current_dir/$selected_name"
                                if [ -d "$new_dir" ]; then
                                    current_dir="$new_dir"
                                fi
                            fi
                            current=0
                            draw_folder_menu
                        fi
                        ;;
                esac
                ;;
        esac
    done
}

# Function to scan for projects
scan_for_projects() {
    local search_dir="$1"

    show_header
    echo -e "${BLUE}Scanning for projects in:${NC} $search_dir"
    echo ""
    echo -e "${DIM}This may take a moment...${NC}"

    local found_projects=()

    # Find directories with common project markers
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue

        # Skip node_modules, .git, etc.
        [[ "$dir" == *"/node_modules/"* ]] && continue
        [[ "$dir" == *"/.git/"* ]] && continue
        [[ "$dir" == *"/dist/"* ]] && continue
        [[ "$dir" == *"/build/"* ]] && continue
        [[ "$dir" == *"/.next/"* ]] && continue
        [[ "$dir" == *"/vendor/"* ]] && continue

        local project_dir=$(dirname "$dir")

        # Check if already in list
        local already_found=false
        for p in "${found_projects[@]}"; do
            [ "$p" = "$project_dir" ] && already_found=true && break
        done
        $already_found && continue

        found_projects+=("$project_dir")
    done < <(find "$search_dir" -maxdepth 4 -type f \( -name "package.json" -o -name "Cargo.toml" -o -name "go.mod" -o -name "pyproject.toml" \) 2>/dev/null)

    if [ ${#found_projects[@]} -eq 0 ]; then
        echo -e "${YELLOW}No projects found.${NC}"
        echo ""
        read -p "Press Enter to continue..."
        return 1
    fi

    # Use interactive multi-select
    if interactive_multiselect "SELECT PROJECTS TO ADD" "${found_projects[@]}"; then
        if [ ${#SELECTED_INDICES[@]} -eq 0 ]; then
            echo ""
            echo -e "${YELLOW}No projects selected.${NC}"
            read -p "Press Enter to continue..."
            return 0
        fi

        # Process selected projects
        for idx in "${SELECTED_INDICES[@]}"; do
            local project="${found_projects[$idx]}"
            show_header
            echo -e "${BLUE}Setting up:${NC} $(basename "$project")"
            echo -e "${DIM}$project${NC}"
            echo ""

            add_project_to_registry "$project"

            if [ ! -f "$project/.ai-workspace.json" ]; then
                echo ""
                read -p "Create .ai-workspace.json? [Y/n] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    create_workspace_config "$project"
                fi
            else
                echo -e "${DIM}(already has .ai-workspace.json)${NC}"
            fi

            echo ""
            read -p "Press Enter to continue to next project..."
        done

        echo ""
        echo -e "${GREEN}✓ Added ${#SELECTED_INDICES[@]} projects${NC}"
    else
        echo ""
        echo -e "${YELLOW}Cancelled.${NC}"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Main menu
main_menu() {
    while true; do
        show_header

        echo -e "${BOLD}What would you like to do?${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC} Scan for projects in a directory"
        echo -e "  ${CYAN}[2]${NC} Add a specific project"
        echo -e "  ${CYAN}[3]${NC} Configure workspace for existing project"
        echo -e "  ${CYAN}[4]${NC} View registered projects"
        echo -e "  ${CYAN}[5]${NC} Check Ghostty permissions"
        echo -e "  ${CYAN}[q]${NC} Quit"
        echo ""
        read -p "Choice: " -n 1 -r choice
        echo ""

        case $choice in
            1)
                echo ""
                if interactive_folder_select "SELECT DIRECTORY TO SCAN" "$HOME"; then
                    scan_for_projects "$SELECTED_PATH"
                else
                    echo -e "${YELLOW}Cancelled${NC}"
                    read -p "Press Enter to continue..."
                fi
                ;;
            2)
                echo ""
                if interactive_folder_select "SELECT PROJECT FOLDER" "$HOME"; then
                    add_project_to_registry "$SELECTED_PATH"
                    read -p "Create .ai-workspace.json? [Y/n] " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        create_workspace_config "$SELECTED_PATH"
                    fi
                else
                    echo -e "${YELLOW}Cancelled${NC}"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                if interactive_folder_select "SELECT PROJECT FOLDER" "$HOME"; then
                    create_workspace_config "$SELECTED_PATH"
                else
                    echo -e "${YELLOW}Cancelled${NC}"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                echo -e "${BLUE}Registered Projects:${NC}"
                echo ""
                jq -r '.projects | to_entries[] | "  \(.key): \(.value.path)"' "$REGISTRY" 2>/dev/null || echo "  No projects registered"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                echo -e "${BLUE}Testing Ghostty Accessibility permissions...${NC}"
                echo ""
                if osascript -e 'tell application "System Events" to keystroke ""' 2>/dev/null; then
                    echo -e "${GREEN}✓${NC} Accessibility permissions OK"
                else
                    echo -e "${RED}✗${NC} Accessibility permissions needed"
                    echo ""
                    echo "To fix:"
                    echo "  1. Open System Settings → Privacy & Security → Accessibility"
                    echo "  2. Add Ghostty and enable it"
                    echo "  3. Restart Ghostty"
                    echo ""
                    read -p "Open System Settings? [Y/n] " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    fi
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            q|Q)
                echo ""
                echo -e "${GREEN}Setup complete!${NC}"
                echo ""
                echo -e "Run ${CYAN}claude-workspace${NC} to launch a project."
                echo ""
                exit 0
                ;;
        esac
    done
}

# Handle command line arguments
if [ -n "$1" ]; then
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Claude Workspace Setup Wizard"
        echo ""
        echo "Usage:"
        echo "  setup.sh              Run interactive setup"
        echo "  setup.sh /path        Setup specific project"
        echo "  setup.sh --help       Show this help"
        exit 0
    elif [ -d "$1" ]; then
        add_project_to_registry "$1"
        create_workspace_config "$1"
        exit 0
    else
        echo -e "${RED}Error: Directory not found: $1${NC}"
        exit 1
    fi
fi

# Run main menu
main_menu
