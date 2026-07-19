#!/usr/bin/env bash
# wayvnc-keepalive — respawn wayvnc if it exits, so port 5900 never stays down.
# Singleton via flock (no double instance after a Hyprland restart). Auto-detects
# WAYLAND_DISPLAY so it also works launched outside the session (SSH/manual).
# (The Moonlight mutual-exclusion flag was removed; wayvnc always runs. During a
#  Moonlight session the panel is dpms-off so VNC would be frozen — not used at the
#  same time, and moonlight-display.sh `off` restarts wayvnc to recover.)
#
# The captured output is detected per respawn rather than hardcoded, so a Hyprland
# restart that renames or re-enumerates outputs is picked up on the next loop.

# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

LOG="$HOME/.local/state/wayvnc.log"
mkdir -p "$(dirname "$LOG")"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for s in "$RT"/wayland-[0-9]*; do
        case "$s" in *.lock) continue ;; esac
        [ -S "$s" ] && WAYLAND_DISPLAY="$(basename "$s")"
    done
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi

# Singleton: prevent two instances racing after a Hyprland restart.
exec 9>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayvnc-keepalive.lock"
flock -n 9 || exit 0

while true; do
    # Resolve the output to capture on every iteration. At boot this unit can win
    # the race against Hyprland, so detection legitimately comes back empty for the
    # first few tries. Launching wayvnc with an empty --output would either fail or
    # capture an arbitrary output (possibly the moonlight headless), so wait and
    # retry instead — the respawn loop is what keeps 5900 from staying down.
    PHYS="$(hypr_primary_monitor)"
    if [ -z "$PHYS" ]; then
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') no physical output yet — retrying in 2s ===" >> "$LOG"
        sleep 2
        continue
    fi

    echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting wayvnc on $PHYS ===" >> "$LOG"
    wayvnc --keyboard=latam --output="$PHYS" 9>&- >> "$LOG" 2>&1
    code=$?
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') wayvnc exited (code $code) — respawning in 2s ===" >> "$LOG"
    sleep 2
done
