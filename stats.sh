#!/usr/bin/env bash
# =============================================================================
# stats.sh — Live status reporter for all series and parallel projects
# Designed to be run via: watch -n 5 ./stats.sh
# Or via the monitor.sh wrapper.
# =============================================================================

# ── Resolve base directory ────────────────────────────────────────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

SERIES_DIR="$BASE_DIR/series"
PARALLEL_DIR="$BASE_DIR/parallel"

# ── ANSI color codes ──────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

COLOR_HEADER="\033[1;37m"       # bold white  — section headers
COLOR_PROJECT="\033[1;36m"      # bold cyan   — project names
COLOR_WORKING="\033[1;33m"      # bold yellow — working / in-progress
COLOR_DONE="\033[1;32m"         # bold green  — done
COLOR_IDLE="\033[2;37m"         # dim grey    — idle
COLOR_ERROR="\033[1;31m"        # bold red    — error
COLOR_DIVIDER="\033[0;90m"      # dark grey   — dividers
COLOR_TREE="\033[0;90m"         # dark grey   — tree branch characters

# ── Terminal width for dynamic divider ───────────────────────────────────────
TERM_WIDTH="${COLUMNS:-80}"
DIVIDER=$(printf "${COLOR_DIVIDER}%${TERM_WIDTH}s${RESET}" | tr ' ' '━')

# ── Tree branch characters ────────────────────────────────────────────────────
BRANCH="├─"
BRANCH_LAST="└─"

# =============================================================================
# SERIES SECTION
# One line per project:
#   project-name   80% - build.sh
#   project-name   done
#   project-name   idle
#   project-name   (no scripts)
# =============================================================================
print_series() {
    printf "${COLOR_HEADER}${BOLD}SERIES${RESET}\n"

    if [[ ! -d "$SERIES_DIR" ]]; then
        printf "  ${COLOR_IDLE}(series/ directory not found)${RESET}\n"
        return
    fi

    local found_any=0

    # Collect all project dirs first to calculate max name width for alignment
    local project_dirs=()
    while IFS= read -r -d '' project_dir; do
        [[ -d "$project_dir" ]] || continue
        project_dirs+=("$project_dir")
    done < <(find "$SERIES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ "${#project_dirs[@]}" -eq 0 ]]; then
        printf "  ${COLOR_IDLE}(no projects found)${RESET}\n"
        return
    fi

    # Calculate max project name length for column alignment
    local max_name_len=0
    for project_dir in "${project_dirs[@]}"; do
        local name
        name="$(basename "$project_dir")"
        (( ${#name} > max_name_len )) && max_name_len=${#name}
    done

    for project_dir in "${project_dirs[@]}"; do
        local project_name
        project_name="$(basename "$project_dir")"
        local status_file="$project_dir/.progress.status"

        # Count .sh files
        local script_count=0
        while IFS= read -r -d ''; do
            (( script_count++ ))
        done < <(find "$project_dir" -maxdepth 1 -name "*.sh" -type f -print0)

        # Build status string
        local status_text
        local status_color

        if [[ $script_count -eq 0 ]]; then
            status_text="(no scripts)"
            status_color="$DIM"
        elif [[ ! -f "$status_file" ]]; then
            status_text="idle"
            status_color="$COLOR_IDLE"
        else
            local percentage_status current_action
            percentage_status=$(sed -n '1p' "$status_file" 2>/dev/null)
            current_action=$(sed -n '2p' "$status_file" 2>/dev/null)
            current_action="${current_action%.sh}"

            case "$percentage_status" in
                done)
                    status_text="done"
                    status_color="$COLOR_DONE"
                    ;;
                error)
                    status_text="error - ${percentage_status}"
                    status_color="$COLOR_ERROR"
                    ;;
                "")
                    status_text="idle"
                    status_color="$COLOR_IDLE"
                    ;;
                *)
                    # In progress: percentage_status in green, filename in dim grey
                    status_text="${COLOR_DONE}${current_action}${RESET}   ${COLOR_WORKING}${percentage_status}${RESET}"
                    status_color=""
                    ;;
            esac
        fi

        printf "  ${COLOR_PROJECT}${BOLD}%-${max_name_len}s${RESET}   ${status_color}%b${RESET}\n" \
            "$project_name" "$status_text"

        found_any=1
    done

    [[ $found_any -eq 0 ]] && printf "  ${COLOR_IDLE}(no projects found)${RESET}\n"
}

# =============================================================================
# PARALLEL SECTION
# Project name on its own line, scripts listed as a tree:
#   project-name
#    ├─ script-one   working
#    └─ script-two   idle
# =============================================================================
print_parallel() {
    printf "${COLOR_HEADER}${BOLD}PARALLEL${RESET}\n"

    if [[ ! -d "$PARALLEL_DIR" ]]; then
        printf "  ${COLOR_IDLE}(parallel/ directory not found)${RESET}\n"
        return
    fi

    local found_any=0
    while IFS= read -r -d '' project_dir; do
        [[ -d "$project_dir" ]] || continue
        local project_name
        project_name="$(basename "$project_dir")"

        printf "  ${COLOR_PROJECT}${BOLD}%s${RESET}" "$project_name"

        # Collect .sh files
        local scripts=()
        while IFS= read -r -d '' f; do
            scripts+=("$f")
        done < <(find "$project_dir" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

        if [[ "${#scripts[@]}" -eq 0 ]]; then
            printf "   ${DIM}(no scripts)${RESET}\n"
            found_any=1
            continue
        fi

        local total="${#scripts[@]}"

        if [[ $total -eq 1 ]]; then
            local script="${scripts[0]}"
            local script_label
            script_label="$(basename "${script%.sh}")"
            local lock_file="${script}.lock"
            local status status_color
            if [[ -f "$lock_file" ]]; then
                status="working"
                status_color="$COLOR_WORKING"
            else
                status="idle"
                status_color="$COLOR_IDLE"
            fi

            printf "   ${COLOR_DONE}%-s${RESET}   ${status_color}%s${RESET}\n" \
                "$script_label" "$status"
            continue
        fi

        printf "\n"

        # Max script label length for column alignment within this project
        local max_len=0
        for script in "${scripts[@]}"; do
            local label
            label="$(basename "${script%.sh}")"
            (( ${#label} > max_len )) && max_len=${#label}
        done

        local idx=0

        for script in "${scripts[@]}"; do
            idx=$(( idx + 1 ))
            local script_label
            script_label="$(basename "${script%.sh}")"
            local lock_file="${script}.lock"

            # Choose branch character
            local branch
            if (( idx == total )); then
                branch="$BRANCH_LAST"
            else
                branch="$BRANCH"
            fi

            local status status_color
            if [[ -f "$lock_file" ]]; then
                status="working"
                status_color="$COLOR_WORKING"
            else
                status="idle"
                status_color="$COLOR_IDLE"
            fi

            printf "    ${COLOR_TREE}%s${RESET} ${COLOR_DONE}%-${max_len}s${RESET}   ${status_color}%s${RESET}\n" \
                "$branch" "$script_label" "$status"
        done

        found_any=1
    done < <(find "$PARALLEL_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    [[ $found_any -eq 0 ]] && printf "  ${COLOR_IDLE}(no projects found)${RESET}\n"
}

# =============================================================================
# HEADER — timestamp so watch output shows freshness
# =============================================================================
printf "🤖 ${BOLD}Auto-Mate Monitor${RESET} ${DIM}• %s${RESET}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "\n"
print_series
printf "\n"
print_parallel

printf "\n%b\n\n" "$DIVIDER"