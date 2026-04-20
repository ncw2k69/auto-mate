#!/usr/bin/env bash
# =============================================================================
# startup.sh — Boot-time initialisation script
#
# Designed to run ONCE at system startup via a systemd oneshot service,
# BEFORE the automation timer begins its regular ticks.
#
# What it does (in order):
#   1. Clears all stale lock files and progress status from the previous session
#   2. Triggers an immediate first run of automation.sh
#
# This guarantees a clean state after a crash, power loss, or reboot, without
# waiting up to 1 minute for the cron/timer to fire for the first time.
#
# Setup: see README.md — "Startup Service (systemd)"
# =============================================================================

# ── Resolve base directory (ultra-portable, follows symlinks) ─────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

AUTOMATION_SCRIPT="$BASE_DIR/automation.sh"

# ── Validate automation.sh is present ────────────────────────────────────────
if [[ ! -f "$AUTOMATION_SCRIPT" ]]; then
    echo "[ERROR] automation.sh not found at $AUTOMATION_SCRIPT"
    exit 1
fi

chmod +x "$AUTOMATION_SCRIPT"

echo "========================================"
echo " Automation Framework — Startup"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# ── STEP 1: Clear all stale locks from previous session ──────────────────────
echo ""
echo "--- Step 1: Clearing stale locks ---"
bash "$AUTOMATION_SCRIPT" --clear-locks

# ── STEP 2: Run automation immediately (don't wait for first cron tick) ───────
echo ""
echo "--- Step 2: First automation run ---"
bash "$AUTOMATION_SCRIPT"

echo ""
echo "========================================"
echo " Startup complete. Regular automation"
echo " will now be handled by cron or the"
echo " systemd automation.timer."
echo "========================================"
