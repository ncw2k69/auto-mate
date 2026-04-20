#!/usr/bin/env bash
# =============================================================================
# serial.sh — Serial folder orchestrator
# Scans all project folders inside series/ and for each one:
#   - Checks its own .lock file (independent per project)
#   - If unlocked, runs its .sh scripts sequentially
#   - All projects are evaluated and launched in parallel with each other
#
# Each project is fully independent — a finished project will re-run on the
# next trigger regardless of whether other projects are still running.
# =============================================================================

# ── Resolve base directory ────────────────────────────────────────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

# ── Internal paths ────────────────────────────────────────────────────────────
LOG_FILE="$BASE_DIR/logs/$(date '+%Y-%m-%d').log"
SERIES_DIR="$BASE_DIR/series"

# ── Logging utility ───────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [serial] $*" >> "$LOG_FILE"
}

# ── Validate series directory ─────────────────────────────────────────────────
if [[ ! -d "$SERIES_DIR" ]]; then
    log "WARN " "series/ directory not found at $SERIES_DIR. Nothing to do."
    exit 0
fi

log "INFO " "Serial orchestrator started (PID $$)"

# =============================================================================
# run_project — handles one serial project folder
# Each call is a fully self-contained subshell (launched with & from below).
# Projects do not know about each other and do not share any state.
# =============================================================================
run_project() {
    local project_dir="$1"
    local project_name
    project_name="$(basename "$project_dir")"

    local lock_file="$project_dir/.lock"
    local status_file="$project_dir/.progress.status"

    # ── Check for existing .lock — this project is still running ─────────────
    if [[ -f "$lock_file" ]]; then
        log "WARN " "[$project_name] .lock present — skipping (still running from previous trigger)"
        return
    fi

    # ── chmod +x all scripts ──────────────────────────────────────────────────
    while IFS= read -r -d '' script; do
        chmod +x "$script"
    done < <(find "$project_dir" -maxdepth 1 -name "*.sh" -type f -print0)

    # ── Collect and sort .sh files ascending ─────────────────────────────────
    local scripts=()
    while IFS= read -r -d '' file; do
        scripts+=("$file")
    done < <(find "$project_dir" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

    local total="${#scripts[@]}"

    if [[ "$total" -eq 0 ]]; then
        log "INFO " "[$project_name] No .sh files found — skipping"
        return
    fi

    # ── Acquire .lock atomically (noclobber prevents race conditions) ──────────
    if ! ( set -C; echo $$ > "$lock_file" ) 2>/dev/null; then
        log "WARN " "[$project_name] Lock race detected — skipping"
        return
    fi

    # ── Ensure lock + status are cleaned up when this subshell exits ──────────
    trap 'rm -f "$lock_file"' EXIT

    # ── Remove stale .progress.status from previous run ───────────────────────
    rm -f "$status_file"

    log "INFO " "[$project_name] Starting execution of $total script(s)"

    # ── Execute scripts sequentially ──────────────────────────────────────────
    local index=0

    for script in "${scripts[@]}"; do
        local script_name
        script_name="$(basename "$script")"
        index=$(( index + 1 ))

        # Progress percentage based on scripts completed so far
        local percent=$(( (index - 1) * 100 / total ))

        # Write .progress.status — two rows only: percentage and current script
        {
            echo "${percent}%"
            echo "$script_name"
        } > "$status_file"

        log "INFO " "[$project_name] Executing ($index/$total): $script_name"

        bash "$script"
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            log "ERROR" "[$project_name] $script_name failed with exit code $exit_code — stopping project"
            # Write error state — reuse two-row format: marker + failed script name
            {
                echo "error"
                echo "$script_name"
            } > "$status_file"
            # .lock removed by trap
            return
        fi

        log "INFO " "[$project_name] Completed: $script_name (exit 0)"
    done

    # ── All scripts completed successfully ────────────────────────────────────
    echo "done" > "$status_file"
    log "INFO " "[$project_name] All $total scripts completed successfully"

    # .lock removed by trap
}

# =============================================================================
# Scan series/ for project folders — launch each as an independent subshell
# =============================================================================
pids=()

while IFS= read -r -d '' project_dir; do
    [[ -d "$project_dir" ]] || continue
    run_project "$project_dir" &
    pids+=($!)
done < <(find "$SERIES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ── Wait for all project subshells ───────────────────────────────────────────
for pid in "${pids[@]}"; do
    wait "$pid"
done

log "INFO " "Serial orchestrator finished"