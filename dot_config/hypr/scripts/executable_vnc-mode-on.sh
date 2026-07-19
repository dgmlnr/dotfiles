#!/usr/bin/env bash
# vnc-mode-on — switch the live session to a virtual 1920x1080 output for remote
# VNC, then power off the physical panel (RDP-style). Triggered on VNC connect.
#
# Why a virtual output: wayvnc mirrors a Wayland OUTPUT, not "the desktop". The
# physical panel (DP-3) is capped at 1600x900, so the only way to serve a crisp
# 1920x1080 to a remote viewer is to give wayvnc a headless output at that size.
#
# Why DPMS (not "monitor,disable"): disabling/removing the output that wayvnc has
# enumerated makes wayvnc crash. DPMS-off blanks the panel while keeping the
# output object alive, so wayvnc never loses a reference. We also point wayvnc at
# the headless BEFORE touching the physical panel.
set -uo pipefail

# Hyprland instance discovery (so this works from SSH, a manual run, or a watcher
# started outside the session) plus the physical-panel detector.
# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/vnc-mode"
mkdir -p "$STATE_DIR"

# Idempotent: if a connect event already armed VNC mode, do nothing.
[ -f "$STATE_DIR/active" ] && exit 0

VNC_RES="1920x1080@60"

# Physical monitor = the active, non-headless output we're currently driving.
# This used to filter on `startswith("HEADLESS") | not`, which let hexdev's
# custom-named "moonlight" headless through and could pick it as the "physical"
# panel. The shared detector matches on empty EDID fields instead, so it is
# immune to whatever a headless output happens to be called.
PHYS="$(hypr_primary_monitor_or_die "vnc-mode-on")" || exit 1

# Remember the workspace the user is actually looking at. Creating the headless
# spawns a fresh empty workspace and focus lands there, so we restore this one
# at the end — otherwise the remote session opens on a blank desktop.
ACTIVE_WS=$(hyprctl monitors -j | jq -r ".[] | select(.name==\"$PHYS\") | .activeWorkspace.id")

# Create the virtual output. Hyprland auto-names it HEADLESS-N (N is not stable
# across creates), so detect the name instead of assuming it. Place it with
# "auto" so it never overlaps the still-enabled physical panel.
hyprctl output create headless
sleep 0.4
HL=$(hyprctl monitors -j | jq -r '.[].name' | grep '^HEADLESS' | head -1)
if [ -z "$HL" ]; then
    echo "vnc-mode-on: headless creation failed" >&2
    exit 1
fi
hyprctl keyword monitor "$HL,$VNC_RES,auto,1"

# Point wayvnc at the virtual output BEFORE blanking the physical one.
wayvncctl output-set "$HL"

# Pin all regular workspaces to the headless so SUPER+N always switches the
# REMOTE view. Otherwise the blanked physical panel grabs a workspace (e.g. 2)
# and SUPER+2 silently jumps focus to the screen you can't see.
for n in 1 2 3 4 5 6 7 8 9 10; do
    hyprctl keyword workspace "$n, monitor:$HL"
done

# Relocate real workspaces (id > 0; skip special/overlay workspaces) onto the
# virtual output, then power off the physical panel via DPMS.
for ws in $(hyprctl workspaces -j | jq -r ".[] | select(.monitor==\"$PHYS\") | select(.id > 0) | .id"); do
    hyprctl dispatch moveworkspacetomonitor "$ws $HL"
done
hyprctl dispatch focusmonitor "$HL"
# Land on the workspace the user had active, not the headless's empty default.
[ -n "$ACTIVE_WS" ] && hyprctl dispatch workspace "$ACTIVE_WS"
hyprctl dispatch dpms off "$PHYS"

# Record what we changed so vnc-mode-off can reverse exactly this.
echo "$PHYS" > "$STATE_DIR/phys"
echo "$HL"   > "$STATE_DIR/headless"
touch "$STATE_DIR/active"
