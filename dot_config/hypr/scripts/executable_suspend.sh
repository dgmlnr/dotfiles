#!/usr/bin/env bash
# Lock, wait until hyprlock is actually up, THEN suspend — so the machine never
# sleeps with an unlocked session.
set -u
SCRIPTS="$HOME/.config/hypr/scripts"
"$SCRIPTS/moonlight-display.sh" off
"$SCRIPTS/lock.sh" &
for _ in $(seq 1 50); do pgrep -x hyprlock >/dev/null && break; sleep 0.1; done

# SAFETY: never suspend with an unlocked session. If hyprlock didn't come up in
# the 5s window (e.g. it crashed at startup — a known hazard on this AMD/aquamarine
# box), ABORT the suspend and warn instead of sleeping wide open.
if ! pgrep -x hyprlock >/dev/null; then
    notify-send -u critical "Suspend cancelado" "hyprlock no arrancó — no suspendo con la sesión desbloqueada." 2>/dev/null || true
    exit 1
fi

sleep 0.5
systemctl suspend
