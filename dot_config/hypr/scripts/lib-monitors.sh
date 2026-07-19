#!/usr/bin/env bash
# lib-monitors.sh — shared display helpers for the Hyprland scripts.
#
# SOURCED, never executed. It only defines functions and sets no shell options,
# so it is safe to pull into callers running under `set -u` / `set -uo pipefail`.
#
# Why this exists: every script used to hardcode DP-3, the work desktop's panel.
# That output does not exist on the laptop (eDP-1 + HDMI-A-1), so those scripts
# were driving an output that was not there — dpms on/off against an unknown name
# is a silent no-op, so the failure was invisible. One detector, sourced by all of
# them, replaces seven copies of the same assumption.

# Make hyprctl reachable when we are launched without the session environment
# (a systemd --user unit, SSH, or a watcher started outside the session).
# One Hyprland instance = one directory under $XDG_RUNTIME_DIR/hypr.
# Always returns 0: a missing signature surfaces as an empty detection result,
# which every caller already has to handle anyway.
hypr_ensure_signature() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && return 0
    local rt d sig=""
    rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for d in "$rt"/hypr/*/; do [ -d "$d" ] && sig="$(basename "$d")"; done
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    return 0
}

# Print the name of the PRIMARY physical output. Prints nothing if none is found.
#
# Selection rule, applied in order:
#
#   1. Keep only REAL outputs. A Hyprland headless output reports EMPTY
#      description/make/model (verified: `hyprctl output create headless` yields
#      description "", make "", model ""), while a physical output always carries
#      its EDID strings. That is what makes this rule name-agnostic — it excludes
#      the auto-named HEADLESS-N outputs that vnc-mode-on.sh creates AND hexdev's
#      custom-named "moonlight" headless, which the older
#      `startswith("HEADLESS") | not` filter silently let through as "physical".
#      Belt and braces, both known headless names are also rejected by name, so a
#      future Hyprland that starts populating those fields for virtual outputs
#      cannot quietly promote one to primary.
#
#   2. Among the real outputs, pick the one at the ORIGIN (x=0, y=0). Both hosts
#      anchor their primary there deliberately and say so in their host file:
#      hexdev pins `monitor = DP-3, preferred, 0x0, 1` so the moonlight headless
#      at 3000x0 keeps a real gap, and hexdev-home anchors the external LG E2340
#      at 0x0 with the notebook parked at -1366x0. It also survives monitor-mode.sh:
#      whichever panel is left running alone gets moved to the origin, so it
#      correctly becomes the primary.
#
#   3. If nothing sits exactly at the origin (an unrecognised machine falling back
#      to the common core's `monitor = , preferred, auto, 1`), take the first real
#      output in Hyprland's own enumeration order rather than giving up.
#
# `hyprctl monitors -j` lists ACTIVE outputs only — one turned off with
# `monitor,disable` only shows up under `monitors all` — which is exactly what we
# want, since a disabled panel must never be chosen as primary. DPMS-off outputs
# DO remain listed, so a blanked panel is still detected; lock.sh, idle-dpms.sh
# and panic-restore.sh depend on that to wake it back up.
hypr_primary_monitor() {
    hypr_ensure_signature
    hyprctl monitors -j 2>/dev/null | jq -r '
        [ .[]
          | select(.disabled != true)
          | select(((.description // "") != "")
                or ((.make // "") != "")
                or ((.model // "") != ""))
          | select((.name | startswith("HEADLESS")) | not)
          | select(.name != "moonlight")
        ] as $real
        | (([ $real[] | select(.x == 0 and .y == 0) ] | first) // ($real | first))
        | .name // empty
    ' 2>/dev/null
}

# Print the name of EVERY real (non-headless) active output, one per line, in
# Hyprland's enumeration order. Same "real output" test as hypr_primary_monitor.
#
# Used where an action must cover the whole physical desk rather than just the
# primary — idle screen-off on the laptop has two panels to blank, and blanking
# only the primary leaves the notebook lit. Deliberately NOT the same as bare
# `hyprctl dispatch dpms off` with no argument, which would also blank hexdev's
# moonlight headless and kill a live stream.
hypr_physical_monitors() {
    hypr_ensure_signature
    hyprctl monitors -j 2>/dev/null | jq -r '
        .[]
        | select(.disabled != true)
        | select(((.description // "") != "")
              or ((.make // "") != "")
              or ((.model // "") != ""))
        | select((.name | startswith("HEADLESS")) | not)
        | select(.name != "moonlight")
        | .name
    ' 2>/dev/null
}

# Same as hypr_primary_monitor but fails loudly instead of printing nothing.
# $1 (optional) names the caller for the error message.
hypr_primary_monitor_or_die() {
    local name
    name="$(hypr_primary_monitor)"
    if [ -z "$name" ]; then
        printf '%s: no physical monitor found\n' "${1:-${0##*/}}" >&2
        return 1
    fi
    printf '%s\n' "$name"
    return 0
}
