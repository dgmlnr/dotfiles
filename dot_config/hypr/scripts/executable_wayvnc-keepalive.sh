#!/usr/bin/env bash
# wayvnc-keepalive — respawn wayvnc if it exits, so port 5900 never stays down.
# Singleton via flock (no double instance after a Hyprland restart). Auto-detects
# WAYLAND_DISPLAY so it also works launched outside the session (SSH/manual).
# (The Moonlight mutual-exclusion flag was removed; wayvnc always runs. During a
#  Moonlight session DP-3 is dpms-off so VNC would be frozen — not used at the same
#  time, and moonlight-display.sh `off` restarts wayvnc to recover.)
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
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') starting wayvnc ===" >> "$LOG"
    wayvnc --keyboard=latam --output=DP-3 9>&- >> "$LOG" 2>&1
    code=$?
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') wayvnc exited (code $code) — respawning in 2s ===" >> "$LOG"
    sleep 2
done
