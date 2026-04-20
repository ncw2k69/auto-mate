#!/usr/bin/env bash
# =============================================================================
# automation.sh — Main entry point
# Triggered every minute by cron or systemd.
# Launches serial.sh and parallel.sh in parallel and exits immediately.
# Overlap protection is handled at the project level via .lock files.
#
# Usage:
#   ./automation.sh                       — normal run
#   ./automation.sh --clear-locks         — clear all locks and status files, then exit
#   ./automation.sh --clear-lock=series   — clear series locks/status only, then exit
#   ./automation.sh --clear-lock=parallel — clear parallel locks only, then exit
# =============================================================================

# ── Resolve base directory (ultra-portable, follows symlinks) ─────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

# ── User-configurable variables ───────────────────────────────────────────────
LOG_RETENTION_DAYS=15

# ── Internal paths ────────────────────────────────────────────────────────────
LOG_FILE="$BASE_DIR/logs/$(date '+%Y-%m-%d').log"
SERIAL_SCRIPT="$BASE_DIR/serial.sh"
PARALLEL_SCRIPT="$BASE_DIR/parallel.sh"
STOP_FILE="$BASE_DIR/process.stop"
SERIES_DIR="$BASE_DIR/series"
PARALLEL_DIR="$BASE_DIR/parallel"

# ── Logging utility ───────────────────────────────────────────────────────────
# Writes to log file AND stdout so startup.sh output is visible in journal logs
log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [automation] $*"
    mkdir -p "$BASE_DIR/logs"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

# ── Ensure logs directory exists ──────────────────────────────────────────────
mkdir -p "$BASE_DIR/logs"

# =============================================================================
# --clear-locks logic
# Clears stale lock files and progress status left over from a previous session.
# Intended to be called by startup.sh on boot, before the first normal run.
# =============================================================================

# ── Helper: clear series project artifacts ────────────────────────────────────
clear_series_locks() {
    log "INFO " "Clearing series locks and status files..."

    if [[ ! -d "$SERIES_DIR" ]]; then
        log "WARN " "series/ directory not found — nothing to clear"
        return
    fi

    local cleared=0

    while IFS= read -r -d '' project_dir; do
        [[ -d "$project_dir" ]] || continue
        local project_name
        project_name="$(basename "$project_dir")"

        if [[ -f "$project_dir/.lock" ]]; then
            rm -f "$project_dir/.lock"
            log "INFO " "  [series/$project_name] Removed .lock"
            (( cleared++ ))
        fi

        if [[ -f "$project_dir/.progress.status" ]]; then
            rm -f "$project_dir/.progress.status"
            log "INFO " "  [series/$project_name] Removed .progress.status"
            (( cleared++ ))
        fi
    done < <(find "$SERIES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ $cleared -eq 0 ]]; then
        log "INFO " "  No series locks or status files found — already clean"
    else
        log "INFO " "  Series cleanup complete ($cleared item(s) removed)"
    fi
}

# ── Helper: clear parallel project artifacts ──────────────────────────────────
clear_parallel_locks() {
    log "INFO " "Clearing parallel lock files..."

    if [[ ! -d "$PARALLEL_DIR" ]]; then
        log "WARN " "parallel/ directory not found — nothing to clear"
        return
    fi

    local cleared=0

    while IFS= read -r -d '' lock_file; do
        local lock_name
        lock_name="$(realpath --relative-to="$BASE_DIR" "$lock_file")"
        rm -f "$lock_file"
        log "INFO " "  Removed $lock_name"
        (( cleared++ ))
    done < <(find "$PARALLEL_DIR" -mindepth 2 -maxdepth 2 -name "*.sh.lock" -print0 | sort -z)

    if [[ $cleared -eq 0 ]]; then
        log "INFO " "  No parallel lock files found — already clean"
    else
        log "INFO " "  Parallel cleanup complete ($cleared item(s) removed)"
    fi
}

# ── Parse arguments ───────────────────────────────────────────────────────────
case "${1:-}" in
    --clear-locks)
        log "INFO " "=== Clear-locks requested (series + parallel) ==="
        clear_series_locks
        clear_parallel_locks
        log "INFO " "=== Clear-locks complete ==="
        exit 0
        ;;
    --clear-lock=series)
        log "INFO " "=== Clear-locks requested (series only) ==="
        clear_series_locks
        log "INFO " "=== Clear-locks complete ==="
        exit 0
        ;;
    --clear-lock=parallel)
        log "INFO " "=== Clear-locks requested (parallel only) ==="
        clear_parallel_locks
        log "INFO " "=== Clear-locks complete ==="
        exit 0
        ;;
    "")
        # Normal run — continue below
        ;;
    *)
        echo "Unknown argument: $1"
        echo "Usage:"
        echo "  $(basename "$0")                         — normal run"
        echo "  $(basename "$0") --clear-locks           — clear all locks and status files"
        echo "  $(basename "$0") --clear-lock=series     — clear series locks and status files"
        echo "  $(basename "$0") --clear-lock=parallel   — clear parallel lock files"
        exit 1
        ;;
esac

# =============================================================================
# Normal run — no arguments passed
# =============================================================================

# ── STEP 1: Check for process.stop kill-switch ────────────────────────────────
if [[ -f "$STOP_FILE" ]]; then
    log "WARN " "process.stop detected — halting execution. Remove the file to resume."
    exit 0
fi

# ── STEP 2: Prune log files older than LOG_RETENTION_DAYS ────────────────────
find "$BASE_DIR/logs" -maxdepth 1 -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null

log "INFO " "Automation triggered"

# ── STEP 3: Launch serial.sh and parallel.sh in parallel, do not wait ─────────
# Project-level .lock files prevent overlapping runs per project.
# automation.sh exits immediately after dispatching both orchestrators.

if [[ -f "$SERIAL_SCRIPT" ]]; then
    bash "$SERIAL_SCRIPT" &
    log "INFO " "Launched serial.sh (PID $!)"
else
    log "WARN " "serial.sh not found at $SERIAL_SCRIPT"
fi

if [[ -f "$PARALLEL_SCRIPT" ]]; then
    bash "$PARALLEL_SCRIPT" &
    log "INFO " "Launched parallel.sh (PID $!)"
else
    log "WARN " "parallel.sh not found at $PARALLEL_SCRIPT"
fi

# ── Exit immediately — orchestrators run independently in the background ───────
log "INFO " "Dispatch complete — automation.sh exiting"