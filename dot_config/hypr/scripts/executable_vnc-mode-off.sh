#!/usr/bin/env bash
# vnc-mode-off — power the physical panel back on (1600x900) and tear down the
# virtual output. Triggered on VNC disconnect, and by the SUPER+CTRL+SHIFT+P panic bind.
#
# Crash-safety: point wayvnc back at the physical output BEFORE removing the
# headless, so wayvnc is never capturing an output we then destroy.
#
# Self-healing: works even if the state files are missing (e.g. an unclean VNC
# drop). It falls back to the detected physical panel and sweeps every headless
# output, so the local screen always comes back.
set -uo pipefail

# Hyprland instance discovery (so this works from SSH, a manual run, or the
# SUPER+CTRL+SHIFT+P panic bind) plus the physical-panel detector.
# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

# RDP-hide guard: if a Moonlight stream is genuinely live, a VNC teardown must NOT
# wake DP-3 or move the desktop back to it — that would expose the remote session on
# the physical panel. Bail and leave the Moonlight setup untouched. (panic-restore.sh
# clears MOON_FLAG first when the user really wants a local restore, so this won't
# block a deliberate double-tap.)
MOON_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/moonlight-active"
if [ -f "$MOON_FLAG" ] && pgrep -x sunshine >/dev/null 2>&1; then
    exit 0
fi

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/vnc-mode"

# Prefer the output vnc-mode-on recorded; if that state is gone (unclean drop),
# fall back to detecting the panel instead of assuming DP-3, which does not exist
# on every host.
PHYS=$(cat "$STATE_DIR/phys" 2>/dev/null)
HL=$(cat "$STATE_DIR/headless" 2>/dev/null)
[ -z "$PHYS" ] && PHYS="$(hypr_primary_monitor)"
if [ -z "$PHYS" ]; then
    echo "vnc-mode-off: no physical monitor found" >&2
    exit 1
fi

# Wake the physical panel back up.
hyprctl dispatch dpms on "$PHYS"
sleep 0.3

# Point wayvnc back at the physical output before we destroy the headless.
wayvncctl output-set "$PHYS" 2>/dev/null

# Move real workspaces back to the physical panel.
if [ -n "$HL" ]; then
    for ws in $(hyprctl workspaces -j | jq -r ".[] | select(.monitor==\"$HL\") | select(.id > 0) | .id"); do
        hyprctl dispatch moveworkspacetomonitor "$ws $PHYS"
    done
fi
hyprctl dispatch focusmonitor "$PHYS"

# Release the workspace pins back to the physical panel.
for n in 1 2 3 4 5 6 7 8 9 10; do
    hyprctl keyword workspace "$n, monitor:$PHYS"
done

# Destroy any leftover headless outputs (skip if locked: removing an output crashes hyprlock).
if ! pgrep -x hyprlock >/dev/null; then
    for h in $(hyprctl monitors -j | jq -r '.[].name' | grep '^HEADLESS'); do
        hyprctl output remove "$h"
    done
fi

rm -f "$STATE_DIR/active" "$STATE_DIR/phys" "$STATE_DIR/headless"
