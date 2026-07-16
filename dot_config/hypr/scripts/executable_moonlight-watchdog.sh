#!/usr/bin/env bash
# moonlight-watchdog — self-heals a stuck local display baseline.
#
# The failure mode: while NO Moonlight stream is live, the off-screen headless
# monitor ends up holding one of the physical workspaces (1..10), or the panel
# stays blanked, or a stale MOON_FLAG lingers. Any of these hides a workspace or
# the panel from the local user (the "can't see workspace 2" bug). This can
# happen through a dirty disconnect, a Hyprland quirk, suspend/resume, etc. — so
# instead of watching for one cause, we watch the STATE and re-assert baseline.
#
# Safety: acting during a live stream would yank the desktop off the remote. So
# "no stream" must be CONFIRMED for CONFIRM_TICKS consecutive checks before any
# correction, and we never touch outputs while hyprlock is running/starting.
#
# Live-stream signal: Sunshine binds UDP video/audio ports ONLY during a session
# (idle = zero UDP sockets, verified on this host). Presence of ANY sunshine UDP
# socket == a stream is live. This is decoupled from MOON_FLAG on purpose, so a
# stale flag is itself a correctable anomaly rather than a blind spot.
#
# Modes:
#   (no args)  run the watchdog loop (default; used by the systemd service)
#   --check    run ONE detection cycle, print verdict, take NO action (dry run)
set -uo pipefail

SCRIPTS="$HOME/.config/hypr/scripts"
DISPLAY_SH="$SCRIPTS/moonlight-display.sh"
HL="moonlight"          # headless output name (matches moonlight-display.sh)
PHYS="DP-3"             # physical panel
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MOON_FLAG="$RT/moonlight-active"
LOCKING="$RT/hyprlock-starting"
INTERVAL="${MOONWD_INTERVAL:-20}"       # seconds between checks
CONFIRM_TICKS="${MOONWD_CONFIRM:-2}"    # consecutive idle checks before acting

# Hyprland env discovery: a systemd --user unit has no HYPRLAND_INSTANCE_SIGNATURE.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    for d in "$RT"/hypr/*/; do [ -d "$d" ] && sig="$(basename "$d")"; done
    export HYPRLAND_INSTANCE_SIGNATURE="${sig:-}"
fi

log() { printf '[moonlight-watchdog] %s\n' "$*" >&2; }

# True while a Moonlight stream is actually live (any sunshine-owned UDP socket).
stream_live() { ss -Huanp 2>/dev/null | grep -q 'sunshine'; }

# True while the screen is locked or a lock is starting: do not touch outputs.
locked() { pgrep -x hyprlock >/dev/null 2>&1 || [ -f "$LOCKING" ]; }

# Emit the list of anomalies found (empty output == healthy). Read-only.
anomalies() {
    local mons wss
    mons="$(hyprctl monitors -j 2>/dev/null)" || return 0
    wss="$(hyprctl workspaces -j 2>/dev/null)" || return 0

    # Headless holding a physical workspace (1..10) while idle.
    if printf '%s' "$wss" | jq -e --arg hl "$HL" \
        '[.[] | select(.monitor==$hl) | select(.id>0 and .id<=10)] | length>0' >/dev/null 2>&1; then
        echo "headless-holds-physical-ws"
    fi
    # Panel blanked (dpms off) while idle — the user can't see anything locally.
    if printf '%s' "$mons" | jq -e --arg p "$PHYS" \
        'any(.[]; .name==$p and (.dpmsStatus==false))' >/dev/null 2>&1; then
        echo "panel-blanked"
    fi
    # Stale session flag while no stream is live.
    [ -f "$MOON_FLAG" ] && echo "stale-moon-flag"
}

# Run one cycle. With $1=act, apply the correction; otherwise dry-run (print only).
cycle() {
    local act="${1:-}"
    if stream_live; then
        [ "$act" = act ] && idle_count=0
        [ "$act" != act ] && log "verdict: STREAM LIVE (sunshine UDP present) — would not act"
        return 0
    fi
    local found; found="$(anomalies | paste -sd, -)"
    if [ "$act" != act ]; then
        if [ -z "$found" ]; then
            log "verdict: idle, healthy — no action needed"
        else
            log "verdict: idle, anomalies=[$found] — would run 'moonlight-display.sh off' after ${CONFIRM_TICKS} confirmed ticks"
        fi
        return 0
    fi
    # Acting loop path: require sustained idle before correcting.
    idle_count=$((idle_count + 1))
    [ "$idle_count" -lt "$CONFIRM_TICKS" ] && return 0
    [ -z "$found" ] && return 0
    if locked; then
        log "anomalies=[$found] but screen is locked — deferring correction"
        return 0
    fi
    log "idle confirmed (${idle_count} ticks), anomalies=[$found] — re-asserting baseline via 'off'"
    "$DISPLAY_SH" off >/dev/null 2>&1 || log "warning: 'moonlight-display.sh off' returned non-zero"
    idle_count=0
}

case "${1:-}" in
    --check) cycle check ;;
    "")
        # Single-instance guard: exec-once + systemd could both launch us.
        exec 9>"$RT/moonlight-watchdog.lock"
        if ! flock -n 9; then
            log "another instance holds the lock — exiting"
            exit 0
        fi
        log "started (interval=${INTERVAL}s, confirm=${CONFIRM_TICKS} ticks)"
        idle_count=0
        while true; do
            cycle act
            sleep "$INTERVAL"
        done
        ;;
    *) echo "uso: $0 [--check]" >&2; exit 1 ;;
esac
