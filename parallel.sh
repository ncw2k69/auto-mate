#!/usr/bin/env bash
# =============================================================================
# parallel.sh — Parallel folder orchestrator
# Scans all project folders inside parallel/ and for each .sh script,
# fires it in the background if no lock file is present.
# The scripts themselves manage their own lock lifecycle (via template).
# Overlap protection is entirely at the script level — no global PID needed.
# =============================================================================

# ── Resolve base directory ────────────────────────────────────────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

# ── Internal paths ────────────────────────────────────────────────────────────
LOG_FILE="$BASE_DIR/logs/$(date '+%Y-%m-%d').log"
PARALLEL_DIR="$BASE_DIR/parallel"

# ── Logging utility ───────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [parallel] $*" >> "$LOG_FILE"
}

# ── Validate parallel directory ───────────────────────────────────────────────
if [[ ! -d "$PARALLEL_DIR" ]]; then
    log "WARN " "parallel/ directory not found at $PARALLEL_DIR. Nothing to do."
    exit 0
fi

log "INFO " "Parallel orchestrator started (PID $$)"

# =============================================================================
# run_project — handles one parallel project folder
# All projects are launched in parallel (background subshells).
# Within each project, each .sh script is fired independently (async).
# =============================================================================
run_project() {
    local project_dir="$1"
    local project_name
    project_name="$(basename "$project_dir")"

    # ── Collect all .sh files ─────────────────────────────────────────────────
    local scripts=()
    while IFS= read -r -d '' file; do
        scripts+=("$file")
    done < <(find "$project_dir" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

    if [[ "${#scripts[@]}" -eq 0 ]]; then
        log "INFO " "[$project_name] No .sh files found — skipping"
        return
    fi

    # ── chmod +x all scripts ──────────────────────────────────────────────────
    for script in "${scripts[@]}"; do
        chmod +x "$script"
    done

    # ── For each script: check lock and fire if free ──────────────────────────
    for script in "${scripts[@]}"; do
        local script_name
        script_name="$(basename "$script")"
        local lock_file="${script}.lock"

        if [[ -f "$lock_file" ]]; then
            log "INFO " "[$project_name] Skipping $script_name — lock file present"
            continue
        fi

        # Fire-and-forget: script manages its own lock via template
        bash "$script" &
        log "INFO " "[$project_name] Launched $script_name (PID $!)"
    done
}

# =============================================================================
# Scan parallel/ for project folders and launch each in parallel
# =============================================================================
pids=()

while IFS= read -r -d '' project_dir; do
    [[ -d "$project_dir" ]] || continue
    run_project "$project_dir" &
    pids+=($!)
done < <(find "$PARALLEL_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ── Wait for all project scan subshells (not the fired scripts themselves) ────
for pid in "${pids[@]}"; do
    wait "$pid"
done

log "INFO " "Parallel orchestrator finished dispatching"