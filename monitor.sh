#!/usr/bin/env bash
# =============================================================================
# monitor.sh — Wrapper for stats.sh using the watch command
#
# Usage:
#   ./monitor.sh          → refresh every 5 seconds (default)
#   ./monitor.sh 2        → refresh every 2 seconds
#   ./monitor.sh 1        → refresh every 1 second
# =============================================================================

# ── Resolve base directory ────────────────────────────────────────────────────
BASE_DIR="$(dirname "$(realpath "$0")")"

STATS_SCRIPT="$BASE_DIR/stats.sh"

# ── Validate interval argument ────────────────────────────────────────────────
INTERVAL="${1:-5}"

if ! [[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$INTERVAL <= 0" | bc -l) )); then
    echo "Usage: $(basename "$0") [interval_seconds]"
    echo "  interval_seconds must be a positive number (default: 5)"
    exit 1
fi

# ── Validate stats.sh exists ──────────────────────────────────────────────────
if [[ ! -f "$STATS_SCRIPT" ]]; then
    echo "Error: stats.sh not found at $STATS_SCRIPT"
    exit 1
fi

chmod +x "$STATS_SCRIPT"

# ── Launch watch ──────────────────────────────────────────────────────────────
exec watch -t -n "$INTERVAL" --color "$STATS_SCRIPT"
