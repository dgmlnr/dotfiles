#!/usr/bin/env bash
# SUPER+L lock wrapper.
# hyprlock crashes ("lockscreen app died") when it tries to render on a DPMS-off
# output: during Moonlight mode the physical panel is blanked, so locking triggers
# endless "atomic drm request: failed to commit: Device or resource busy" and
# hyprlock dies. Fix: wake the physical panel before locking, then re-blank it
# after unlock if we are still in Moonlight mode (the "moonlight" headless is present).
set -u

# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

LOCKING="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprlock-starting"
MOON_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/moonlight-active"

# Primary physical output, detected at runtime (DP-3 on hexdev, the external LG on
# the laptop). Resolved once here so the post-unlock re-blank targets the very same
# output we woke, even if the layout changed while the session was locked.
PHYS="$(hypr_primary_monitor)"

# Refuse to stack a second locker. This used to live as `pidof hyprlock || ...`
# duplicated at both call sites (hyprland.conf's SUPER+Escape bind and
# hypridle.conf's lock_cmd). It belongs here instead: one copy, and one place
# where the failure direction is written down.
#
# This guard FAILS OPEN, deliberately, and that is the opposite of the one in
# idle-dpms.sh. There, "cannot tell" must not blank, because blanking under a
# lock crashes hyprlock. Here, "cannot tell" must still lock: stacking two
# hyprlocks is ugly, but failing to lock leaves the session open to anyone
# walking past. So only a positive detection from a detector we know ran stops
# us -- a missing or broken pgrep falls through and locks.
#
# It also has to sit above the touch/trap below: exiting after the trap is armed
# would delete the FIRST locker's marker on the way out.
if command -v pgrep >/dev/null 2>&1 && pgrep -x hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Marker so moonlight-display.sh 'on' won't dpms-off the panel during the window
# before hyprlock has grabbed the session lock (that race crashes hyprlock on this AMD).
touch "$LOCKING"
trap 'rm -f "$LOCKING"' EXIT

# Never lock without waking the panel first. If detection failed there is nothing
# safe to wake, so just lock — better a lock on an odd layout than no lock at all.
if [ -n "$PHYS" ]; then
    hyprctl dispatch dpms on "$PHYS"
    sleep 0.3
fi
hyprlock          # blocks until the user authenticates

# Re-blank the panel only if a Moonlight session is genuinely live (flag present AND
# sunshine running) AND no hyprlock remains (duplicate SUPER+L safety).
# Using the canonical flag+process check instead of a workspace-windows heuristic,
# which fails when only special/scratchpad windows are open.
if [ -n "$PHYS" ] && ! pgrep -x hyprlock >/dev/null \
   && [ -f "$MOON_FLAG" ] && pgrep -x sunshine >/dev/null; then
    hyprctl dispatch dpms off "$PHYS"
fi
