#!/usr/bin/env bash
# SUPER+CTRL+SHIFT+P panic restore — remote-aware screen recovery.
#
# Behaviour:
#   - Single press while a Moonlight stream is GENUINELY live -> re-assert the
#     remote hide (the panel stays off+empty). Prevents an accidental press from
#     exposing the remote session on the physical panel (the 14-jun incident).
#   - Double press within 3s -> force a full LOCAL restore, overriding the guard
#     ("I'm physically here, give me the panel NOW", even if a flag is stale).
#   - No live remote -> full LOCAL restore: vnc-mode-off (sweeps VNC HEADLESS-*,
#     wakes the panel), moonlight off (desktop back to the panel), wake the panel.
# "Genuinely live" = MOON_FLAG present AND sunshine running, so a stale flag can
# never lock the user out of the local panel.
set -uo pipefail

# Hyprland instance discovery plus the physical-panel detector.
# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

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
rm -f "$MOON_FLAG"                    # clear so the teardowns run fully and the panel wakes
"$SCRIPTS/vnc-mode-off.sh"            # VNC teardown: sweeps HEADLESS-*, wakes the panel
"$SCRIPTS/moonlight-display.sh" off   # moonlight teardown: desktop back to the panel, restart wayvnc

# Belt: ensure the physical panel is awake. This is the "I am standing here and I
# want my screen back" path, so it wakes EVERY real output rather than just the
# primary — on a two-panel host, restoring only one of them is still a broken desk.
# If detection comes back empty we fall back to a bare `dpms on`, which targets all
# outputs: waking a headless too is harmless, and having no screen at all is not.
MONS="$(hypr_physical_monitors)"
if [ -n "$MONS" ]; then
    for m in $MONS; do hyprctl dispatch dpms on "$m"; done
else
    hyprctl dispatch dpms on
fi

rm -f "$STAMP"                        # reset double-tap clock so a later unrelated press starts fresh
