#!/usr/bin/env bash
# SUPER+L lock wrapper.
# hyprlock crashes ("lockscreen app died") when it tries to render on a DPMS-off
# output: during Moonlight mode DP-3 is blanked, so locking triggers endless
# "atomic drm request: failed to commit: Device or resource busy" and hyprlock dies.
# Fix: wake the physical panel before locking, then re-blank it after unlock if we
# are still in Moonlight mode (the "moonlight" headless is present).
set -u

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for d in "$RT"/hypr/*/; do [ -d "$d" ] && sig="$(basename "$d")"; done
    export HYPRLAND_INSTANCE_SIGNATURE="${sig:-}"
fi

LOCKING="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprlock-starting"
MOON_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/moonlight-active"

# Marker so moonlight-display.sh 'on' won't dpms-off DP-3 during the window before
# hyprlock has grabbed the session lock (that race crashes hyprlock on this AMD).
touch "$LOCKING"
trap 'rm -f "$LOCKING"' EXIT

hyprctl dispatch dpms on DP-3
sleep 0.3
hyprlock          # blocks until the user authenticates

# Re-blank DP-3 only if a Moonlight session is genuinely live (flag present AND
# sunshine running) AND no hyprlock remains (duplicate SUPER+L safety).
# Using the canonical flag+process check instead of a workspace-windows heuristic,
# which fails when only special/scratchpad windows are open.
if ! pgrep -x hyprlock >/dev/null && [ -f "$MOON_FLAG" ] && pgrep -x sunshine >/dev/null; then
    hyprctl dispatch dpms off DP-3
fi
