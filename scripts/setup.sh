#!/bin/bash

#══════════════════════════════════════════════════════════════════════════════
#  CLAUDE WORKSPACE SETUP WIZARD
#══════════════════════════════════════════════════════════════════════════════
#
#  Interactive setup wizard to:
#  - Find and register projects
#  - Create .claude-workspace.json configs
#  - Configure dev processes
#
#  USAGE:
#    setup.sh
#    setup.sh /path/to/project    # Setup specific project
#
#══════════════════════════════════════════════════════════════════════════════

INSTALL_DIR="$HOME/.claude-workspace"
REGISTRY="$INSTALL_DIR/registry.json"

# Source the menu library for flicker-free menus
source "$INSTALL_DIR/scripts/lib/menu.sh"

# Theme colors (matching menu.sh polished theme)
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Semantic colors - 256-color codes for better terminal compatibility
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

# Legacy aliases for compatibility
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

# Clean polished header - no box characters
show_header() {
    local use_clear=${1:-true}
    if [ "$use_clear" = true ]; then
        goto_row 1
    fi
    clear_line
    echo ""
    clear_line
    echo -e "    ${TEXT}${BOLD}Setup Wizard${NC}"
    clear_line
    echo ""
}

# Draw header once (for alt screen initial draw)
draw_header_once() {
    goto_row 1
    echo ""
    echo -e "    ${TEXT}${BOLD}Setup Wizard${NC}                                                               ${TEXT_MUTED}esc${NC}"
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
    local config_file="$project_path/.claude-workspace.json"

    show_header
    echo -e "${BOLD}Setting up workspace for:${NC} $(basename "$project_path")"
    echo -e "${BLUE}Path:${NC} $project_path"
    echo ""

    local suggestions=$(detect_project_type "$project_path")

    echo ""

    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}Existing .claude-workspace.json found.${NC}"
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

# Interactive multi-select function - polished style
# Usage: interactive_select "Title" array[@] selected[@]
# Returns selected indices in SELECTED_INDICES array
interactive_multiselect() {
    local title="$1"
    shift
    local -a items=("$@")
    local total=${#items[@]}
    local ITEMS_ROW=7  # Row where items start

    # Initialize selection state (all unselected)
    local -a selected=()
    for ((i=0; i<total; i++)); do
        selected[$i]=0
    done

    local current=0

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw static header
    draw_static() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}$title${NC}                                                                   ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Select projects to add to registry${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Projects${NC}  ${TEXT_DIM}space to toggle · a: all · n: none${NC}"
    }

    # Draw a single item
    draw_item() {
        local i=$1
        local row=$((ITEMS_ROW + i))

        local item="${items[$i]}"
        local name=$(basename "$item")
        local checkbox="○"
        local status=""

        [ -f "$item/.claude-workspace.json" ] && status="configured"

        if [ "${selected[$i]}" -eq 1 ]; then
            checkbox="${SUCCESS}●${NC}"
        fi

        goto_row $row
        clear_line
        if [ $i -eq $current ]; then
            echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} $checkbox $name ${NC}${PRIMARY_BG}${PRIMARY_FG} $status ${NC}"
        else
            echo -e "     $checkbox ${TEXT}$name${NC} ${TEXT_MUTED}$status${NC}"
        fi
    }

    # Draw all items
    draw_all_items() {
        for ((i=0; i<total; i++)); do
            draw_item $i
        done
    }

    # Draw footer with count
    draw_footer() {
        local count=0
        for s in "${selected[@]}"; do
            [ "$s" -eq 1 ] && ((count++))
        done

        goto_row $((ITEMS_ROW + total + 2))
        clear_line
        echo -e "    ${TEXT_MUTED}$count of $total selected${NC}"
    }

    # Initial draw
    draw_static
    draw_all_items
    draw_footer

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                SELECTED_INDICES=()
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            a|A)  # Select all
                for ((i=0; i<total; i++)); do
                    selected[$i]=1
                done
                draw_all_items
                draw_footer
                ;;
            n|N)  # Select none
                for ((i=0; i<total; i++)); do
                    selected[$i]=0
                done
                draw_all_items
                draw_footer
                ;;
            " ")  # Space - toggle selection
                if [ "${selected[$current]}" -eq 1 ]; then
                    selected[$current]=0
                else
                    selected[$current]=1
                fi
                draw_item $current
                draw_footer
                ;;
            "")  # Enter - confirm
                show_cursor
                exit_alt_screen
                trap - EXIT
                break
                ;;
            $'\x1b')  # Escape sequence (arrow keys)
                read -rsn2 -t 1 seq
                if [ -z "$seq" ]; then
                    # Just escape - cancel
                    SELECTED_INDICES=()
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    return 1
                fi
                local prev=$current
                case "$seq" in
                    '[A')  # Up arrow
                        ((current--))
                        [ $current -lt 0 ] && current=$((total - 1))
                        if [ $prev -ne $current ]; then
                            draw_item $prev
                            draw_item $current
                        fi
                        ;;
                    '[B')  # Down arrow
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

    # Build result array
    SELECTED_INDICES=()
    for ((i=0; i<total; i++)); do
        if [ "${selected[$i]}" -eq 1 ]; then
            SELECTED_INDICES+=($i)
        fi
    done

    return 0
}

# Interactive folder navigator - polished style
# Usage: interactive_folder_select "Title" [start_path]
# Returns selected path in SELECTED_PATH variable
interactive_folder_select() {
    local title="$1"
    local current_dir="${2:-$HOME}"
    local HEADER_ROWS=9  # Header + hint + current path
    local MAX_VISIBLE=15

    # Normalize path
    current_dir="${current_dir/#\~/$HOME}"
    [ ! -d "$current_dir" ] && current_dir="$HOME"

    local current=0
    local show_hidden=false

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

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

    # Draw static header
    draw_static_header() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}$title${NC}                                                                   ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Navigate to select a folder${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Folders${NC}  ${TEXT_DIM}s: select · enter: open${NC}"
    }

    # Draw current path
    draw_current_path() {
        goto_row 7
        clear_line
        echo -e "    ${TEXT_MUTED}Path:${NC} ${TEXT}${BOLD}$current_dir${NC}"
        clear_line
        echo ""
    }

    # Draw folder list
    draw_folder_list() {
        # Get directories
        local -a dirs=()
        while IFS= read -r line; do
            [ -n "$line" ] && dirs+=("$line")
        done < <(get_dirs "$current_dir")
        local total=${#dirs[@]}

        goto_row $HEADER_ROWS
        clear_below

        if [ $total -eq 0 ]; then
            echo -e "    ${TEXT_DIM}(empty directory)${NC}"
        else
            # Calculate visible range
            local start=0
            local end=$total

            if [ $total -gt $MAX_VISIBLE ]; then
                start=$((current - MAX_VISIBLE/2))
                [ $start -lt 0 ] && start=0
                end=$((start + MAX_VISIBLE))
                [ $end -gt $total ] && end=$total && start=$((end - MAX_VISIBLE))
            fi

            [ $start -gt 0 ] && echo -e "    ${TEXT_DIM}↑ more${NC}"

            for ((i=start; i<end; i++)); do
                local name="${dirs[$i]}"

                if [ $i -eq $current ]; then
                    echo -e "    ${PRIMARY_BG}${PRIMARY_FG}${BOLD} $name ${NC}"
                else
                    echo -e "     ${TEXT}$name${NC}"
                fi
            done

            [ $end -lt $total ] && echo -e "    ${TEXT_DIM}↓ more${NC}"
        fi
    }

    # Initial draw
    draw_static_header
    draw_current_path
    draw_folder_list

    while true; do
        read -rsn1 key

        # Get current dirs for navigation
        local -a dirs=()
        while IFS= read -r line; do
            [ -n "$line" ] && dirs+=("$line")
        done < <(get_dirs "$current_dir")
        local total=${#dirs[@]}

        case "$key" in
            q|Q)
                SELECTED_PATH=""
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 1
                ;;
            s|S)  # Select current folder
                SELECTED_PATH="$current_dir"
                show_cursor
                exit_alt_screen
                trap - EXIT
                return 0
                ;;
            h|H)  # Toggle hidden files (future enhancement)
                show_hidden=!$show_hidden
                current=0
                draw_folder_list
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
                    draw_current_path
                    draw_folder_list
                fi
                ;;
            $'\x1b')  # Escape sequence (arrow keys)
                read -rsn2 -t 1 seq
                if [ -z "$seq" ]; then
                    # Just escape - cancel
                    SELECTED_PATH=""
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    return 1
                fi
                case "$seq" in
                    '[A')  # Up arrow
                        ((current--))
                        [ $current -lt 0 ] && current=$((total > 0 ? total - 1 : 0))
                        draw_folder_list
                        ;;
                    '[B')  # Down arrow
                        ((current++))
                        [ $current -ge $total ] && current=0
                        draw_folder_list
                        ;;
                    '[D')  # Left arrow - go to parent
                        if [ "$current_dir" != "/" ]; then
                            current_dir=$(dirname "$current_dir")
                            current=0
                            draw_current_path
                            draw_folder_list
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
                            draw_current_path
                            draw_folder_list
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

            if [ ! -f "$project/.claude-workspace.json" ]; then
                echo ""
                read -p "Create .claude-workspace.json? [Y/n] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    create_workspace_config "$project"
                fi
            else
                echo -e "${DIM}(already has .claude-workspace.json)${NC}"
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

# Main menu - polished style
main_menu() {
    # Menu items: id, label, description
    local -a menu_ids=("scan" "add" "configure" "view" "settings" "ghostty" "quit")
    local -a menu_labels=(
        "Scan for Projects"
        "Add Project"
        "Configure Workspace"
        "View Projects"
        "AI Settings"
        "Check Ghostty"
        "Done"
    )
    local -a menu_descs=(
        "Scan directory for projects"
        "Add a specific folder"
        "Edit .claude-workspace.json"
        "List registered projects"
        "AI tools and delegation"
        "Test accessibility"
        "Exit setup"
    )
    local total=${#menu_ids[@]}
    local current=0
    local ITEMS_ROW=7

    enter_alt_screen
    hide_cursor
    trap 'show_cursor; exit_alt_screen' EXIT

    # Draw header
    draw_header() {
        goto_row 1
        echo ""
        echo -e "    ${TEXT}${BOLD}Setup Wizard${NC}                                                               ${TEXT_MUTED}esc${NC}"
        echo ""
        echo -e "    ${TEXT_MUTED}Configure projects and workspaces${NC}"
        echo ""
        echo -e "    ${ACCENT}${BOLD}Options${NC}"
    }

    # Draw single item
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
        :  # No-op
    }

    # Initial draw
    draw_header
    draw_all_items
    draw_description

    while true; do
        read -rsn1 key

        case "$key" in
            q|Q)
                show_cursor
                exit_alt_screen
                trap - EXIT
                echo ""
                echo -e "${GREEN}Setup complete!${NC}"
                echo ""
                echo -e "Run ${CYAN}claude-workspace${NC} to launch a project."
                echo ""
                exit 0
                ;;
            "")  # Enter - select current item
                local selected_id="${menu_ids[$current]}"
                case "$selected_id" in
                    scan)
                        if interactive_folder_select "SELECT DIRECTORY TO SCAN" "$HOME"; then
                            show_cursor
                            exit_alt_screen
                            clear
                            scan_for_projects "$SELECTED_PATH"
                            enter_alt_screen
                            hide_cursor
                        fi
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    add)
                        if interactive_folder_select "SELECT PROJECT FOLDER" "$HOME"; then
                            show_cursor
                            exit_alt_screen
                            clear
                            add_project_to_registry "$SELECTED_PATH"
                            read -p "Create .claude-workspace.json? [Y/n] " -n 1 -r
                            echo
                            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                                create_workspace_config "$SELECTED_PATH"
                            fi
                            echo ""
                            read -p "Press Enter to continue..."
                            enter_alt_screen
                            hide_cursor
                        fi
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    configure)
                        if interactive_folder_select "SELECT PROJECT FOLDER" "$HOME"; then
                            show_cursor
                            exit_alt_screen
                            clear
                            create_workspace_config "$SELECTED_PATH"
                            echo ""
                            read -p "Press Enter to continue..."
                            enter_alt_screen
                            hide_cursor
                        fi
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    view)
                        show_cursor
                        goto_row $((ITEMS_ROW + total + 4))
                        clear_below
                        echo -e "${BLUE}Registered Projects:${NC}"
                        echo ""
                        jq -r '.projects | to_entries[] | "  \(.key): \(.value.path)"' "$REGISTRY" 2>/dev/null || echo "  No projects registered"
                        echo ""
                        read -p "Press Enter to continue..."
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    settings)
                        show_cursor
                        exit_alt_screen
                        "$INSTALL_DIR/scripts/settings.sh"
                        enter_alt_screen
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    ghostty)
                        show_cursor
                        goto_row $((ITEMS_ROW + total + 4))
                        clear_below
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
                        hide_cursor
                        draw_header
                        draw_all_items
                        draw_description
                        ;;
                    quit)
                        show_cursor
                        exit_alt_screen
                        trap - EXIT
                        echo ""
                        echo -e "${GREEN}Setup complete!${NC}"
                        echo ""
                        echo -e "Run ${CYAN}claude-workspace${NC} to launch a project."
                        echo ""
                        exit 0
                        ;;
                esac
                ;;
            $'\x1b')  # Escape sequence
                read -rsn2 -t 1 seq
                if [ -z "$seq" ]; then
                    # Just escape - quit
                    show_cursor
                    exit_alt_screen
                    trap - EXIT
                    echo ""
                    echo -e "${SUCCESS}Setup complete!${NC}"
                    echo ""
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
