#!/usr/bin/env bash
# Moonlight 1920 mode (Sunshine global_prep_cmd) + persistent virtual display.
# The mutual-exclusion flag was REMOVED (it caused orphan lock-outs). wayvnc now
# always runs; during a Moonlight session the panel is dpms-off so VNC would be
# frozen (don't use both at once) — `off` restarts wayvnc to recover.
#   init : create the headless once, park it off-screen, keep the desktop on the panel.
#   on   : move the desktop onto the headless; blank the panel (skipped if locked/locking).
#   off  : move the desktop back to the panel; wake it; restart wayvnc. Headless STAYS.
# RULES: DPMS only, never monitor,disable. Never create/destroy/dpms-off an output under lock.
#
# HOST SCOPE: this is a hexdev-only script (it is the Sunshine global_prep_cmd on the
# remote-access server). The panel is still detected rather than hardcoded so it
# survives a port change on that box and cannot silently no-op if DP-3 is renamed.
set -uo pipefail

# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

HL="moonlight"
RES="1920x1080@60"
POS="3000x0"

# Physical panel, detected at runtime. The detector excludes headless outputs by
# their empty EDID fields, so "$HL" below can never be picked as the panel even
# though its name looks nothing like HEADLESS-N.
PHYS="$(hypr_primary_monitor_or_die "moonlight-display")" || exit 1
LOCKING="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprlock-starting"
# Set while a Moonlight session is engaged (desktop on the headless, DP-3 hidden).
# Read by panic-restore.sh and vnc-mode-off.sh to keep the physical panel hidden
# while a remote is live. Sanity-checked elsewhere against a live `sunshine` process
# so a stale flag (sunshine crash) never locks the user out of the local panel.
MOON_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/moonlight-active"

ensure_headless() {
    if hyprctl monitors all -j | jq -e --arg n "$HL" 'any(.[]; .name==$n)' >/dev/null 2>&1; then
        hyprctl keyword monitor "$HL,$RES,$POS,1" >/dev/null 2>&1 || true
        return 0
    fi
    # Creating an output while hyprlock is active OR starting crashes hyprlock -> abort.
    if pgrep -x hyprlock >/dev/null || [ -f "$LOCKING" ]; then
        return 1
    fi
    hyprctl output create headless "$HL"
    sleep 0.6
    hyprctl keyword monitor "$HL,$RES,$POS,1" >/dev/null 2>&1 || true
    return 0
}

ws_move() {  # move all real workspaces from monitor $1 to monitor $2
    for ws in $(hyprctl workspaces -j | jq -r ".[] | select(.monitor==\"$1\") | select(.id > 0) | .id"); do
        hyprctl dispatch moveworkspacetomonitor "$ws $2"
    done
}

case "${1:-}" in
    init)
        rm -f "$MOON_FLAG"   # init is a local-baseline state, not a live session
        ensure_headless
        sleep 0.4
        for n in 1 2 3 4 5 6 7 8 9 10; do hyprctl keyword workspace "$n, monitor:$PHYS"; done
        ws_move "$HL" "$PHYS"
        hyprctl dispatch focusmonitor "$PHYS"
        ;;
    on)
        if ! ensure_headless; then
            # Locked + headless missing: creating it would crash hyprlock. Leave DP-3
            # visible so the user can unlock; headless is created on reconnect.
            hyprctl dispatch dpms on "$PHYS"
            exit 0
        fi
        # Only capture the active workspace on a fresh engage; on a re-assert
        # (MOON_FLAG already set) DP-3 is dpms-off/empty and ACTIVE_WS would be
        # stale, causing an unexpected workspace switch on the Moonlight viewer.
        ACTIVE_WS=""
        [ ! -f "$MOON_FLAG" ] && ACTIVE_WS=$(hyprctl monitors -j | jq -r ".[] | select(.name==\"$PHYS\") | .activeWorkspace.id")
        for n in 1 2 3 4 5 6 7 8 9 10; do hyprctl keyword workspace "$n, monitor:$HL"; done
        ws_move "$PHYS" "$HL"
        hyprctl dispatch focusmonitor "$HL"
        [ -n "${ACTIVE_WS:-}" ] && hyprctl dispatch workspace "$ACTIVE_WS"
        # Don't blank DP-3 if hyprlock is running OR about to start (lock.sh marker).
        if ! pgrep -x hyprlock >/dev/null && [ ! -f "$LOCKING" ]; then
            hyprctl dispatch dpms off "$PHYS"
        fi
        # Mark the Moonlight session engaged (desktop is on the headless now).
        touch "$MOON_FLAG"
        ;;
    off)
        rm -f "$MOON_FLAG"   # session ending: clear before restoring the panel
        hyprctl dispatch dpms on "$PHYS"
        sleep 0.3
        ws_move "$HL" "$PHYS"
        hyprctl dispatch focusmonitor "$PHYS"
        for n in 1 2 3 4 5 6 7 8 9 10; do hyprctl keyword workspace "$n, monitor:$PHYS"; done
        # Restart wayvnc so it re-captures the now-awake DP-3 (clears any stuck "paused" state).
        pkill -x wayvnc 2>/dev/null || true
        ;;
    *)
        echo "uso: $0 init|on|off" >&2; exit 1 ;;
esac
