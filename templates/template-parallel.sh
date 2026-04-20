#!/usr/bin/env bash
# =============================================================================
# template-parallel.sh — Template for Parallel Project Scripts
#
# HOW TO USE:
#   1. Copy this file into your project folder inside parallel/
#      e.g.  cp template-parallel.sh parallel/my-project/my-script.sh
#   2. Rename it to something meaningful (e.g. analyze.sh, fetch-data.sh)
#   3. Add your python or bun calls in the section marked below
#   4. Do NOT manually create or delete the .lock file — this template
#      handles it automatically, including on crashes or kills.
# =============================================================================

# ── Resolve script identity (works even when called via symlink) ──────────────
SCRIPT_FILENAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOCK_FILE="$SCRIPT_DIR/${SCRIPT_FILENAME}.lock"

# ── Atomic lock creation ──────────────────────────────────────────────────────
# If another instance is already running (lock exists), exit immediately.
# Uses noclobber (set -C) to prevent race conditions.
if ! ( set -C; echo $$ > "$LOCK_FILE" ) 2>/dev/null; then
    # Lock already exists — another instance is running, nothing to do
    exit 0
fi

# ── Always remove the lock on exit (normal finish, error, or kill signal) ─────
trap 'rm -f "$LOCK_FILE"' EXIT

# =============================================================================
# YOUR CODE BELOW
# Add your python or bun calls here.
#
# Examples:
#   python3 /absolute/path/to/your_script.py
#   python3 "$(dirname "$(realpath "$0")")/your_script.py"
#
#   bun run /absolute/path/to/your_script.js
#   bun run "$(dirname "$(realpath "$0")")/your_script.js"
#
# Notes:
#   - The lock file is active for the entire duration of this script.
#   - If your script crashes, the lock is still removed automatically.
#   - Keep heavy work inside the external python/bun process.
#   - You can chain multiple calls sequentially here if needed.
# =============================================================================

# python3 "$(dirname "$(realpath "$0")")/your_script.py"
# bun run "$(dirname "$(realpath "$0")")/your_script.js"
