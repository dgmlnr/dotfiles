#!/usr/bin/env bash
# SUPER+CTRL+SHIFT+P panic restore — remote-aware screen recovery.
#
# Behaviour:
#   - Single press while a Moonlight stream is GENUINELY live -> re-assert the
#     remote hide (DP-3 stays off+empty). Prevents an accidental press from
#     exposing the remote session on the physical panel (the 14-jun incident).
#   - Double press within 3s -> force a full LOCAL restore, overriding the guard
#     ("I'm physically here, give me the panel NOW", even if a flag is stale).
#   - No live remote -> full LOCAL restore: vnc-mode-off (sweeps VNC HEADLESS-*,
#     dpms on DP-3), moonlight off (desktop back to DP-3), wake DP-3.
# "Genuinely live" = MOON_FLAG present AND sunshine running, so a stale flag can
# never lock the user out of the local panel.
set -uo pipefail

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for d in "$RT"/hypr/*/; do [ -d "$d" ] && sig="$(basename "$d")"; done
    export HYPRLAND_INSTANCE_SIGNATURE="${sig:-}"
fi

SCRIPTS="$HOME/.config/hypr/scripts"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MOON_FLAG="$RT/moonlight-active"
STAMP="$RT/panic-last"

# Double-tap detection: record now, compare to the previous press.
now=$(date +%s)
last=$(cat "$STAMP" 2>/dev/null || echo 0)
echo "$now" > "$STAMP"
double_tap=0
[ "$((now - last))" -le 3 ] && double_tap=1

# A Moonlight session counts as live only if the flag is set AND sunshine runs.
moonlight_live() { [ -f "$MOON_FLAG" ] && pgrep -x sunshine >/dev/null 2>&1; }

if [ "$double_tap" -eq 0 ] && moonlight_live; then
    # Remote is live and this is a single press: keep DP-3 hidden, just re-assert
    # the Moonlight view. Never wake the physical panel.
    "$SCRIPTS/moonlight-display.sh" on
    exit 0
fi

# No live remote (or a deliberate double-tap): full LOCAL restore.
rm -f "$MOON_FLAG"                    # clear so the teardowns run fully and DP-3 wakes
"$SCRIPTS/vnc-mode-off.sh"            # VNC teardown: sweeps HEADLESS-*, dpms on DP-3
"$SCRIPTS/moonlight-display.sh" off   # moonlight teardown: desktop back to DP-3, restart wayvnc
hyprctl dispatch dpms on DP-3         # belt: ensure the physical panel is awake
rm -f "$STAMP"                        # reset double-tap clock so a later unrelated press starts fresh
