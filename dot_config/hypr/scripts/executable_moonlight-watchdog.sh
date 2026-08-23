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
# Live-stream signal: Sunshine binds its session UDP ports (video/control/audio
# = 47998/47999/48000 with the default 47989 port base) ONLY during a session
# (idle = zero UDP sockets, verified on this host). Detection is by PORT, never
# by `ss -p` process name: sunshine's file capabilities make the kernel refuse
# socket->process attribution to non-root `ss`, so a name match silently never
# fires and every live session reads as idle. This is decoupled from MOON_FLAG
# on purpose, so a stale flag is itself a correctable anomaly, not a blind spot.
#
# Modes:
#   (no args)  run the watchdog loop (default; used by the systemd service)
#   --check    run ONE detection cycle, print verdict, take NO action (dry run)
set -uo pipefail

SCRIPTS="$HOME/.config/hypr/scripts"
DISPLAY_SH="$SCRIPTS/moonlight-display.sh"
HL="moonlight"          # headless output name (matches moonlight-display.sh)
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MOON_FLAG="$RT/moonlight-active"
LOCKING="$RT/hyprlock-starting"
INTERVAL="${MOONWD_INTERVAL:-20}"       # seconds between checks
CONFIRM_TICKS="${MOONWD_CONFIRM:-2}"    # consecutive idle checks before acting

# Hyprland env discovery (a systemd --user unit has no HYPRLAND_INSTANCE_SIGNATURE)
# plus the physical-panel detector.
# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

# Physical panel. Re-resolved every cycle rather than captured once at startup:
# this is a long-running daemon that outlives monitor hotplugs and Hyprland
# restarts, so a name pinned at boot could go stale and make the panel-blanked
# check silently match nothing forever.
PHYS=""

log() { printf '[moonlight-watchdog] %s\n' "$*" >&2; }

# True while a Moonlight stream is actually live (any session UDP port bound).
stream_live() {
    [ -n "$(ss -Huan '( sport = :47998 or sport = :47999 or sport = :48000 )' 2>/dev/null)" ]
}

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
    # Guarded on a non-empty $PHYS so a failed detection degrades to "can't tell"
    # instead of matching a monitor whose name is the empty string.
    if [ -n "$PHYS" ] && printf '%s' "$mons" | jq -e --arg p "$PHYS" \
        'any(.[]; .name==$p and (.dpmsStatus==false))' >/dev/null 2>&1; then
        echo "panel-blanked"
    fi
    # Stale session flag while no stream is live.
    [ -f "$MOON_FLAG" ] && echo "stale-moon-flag"
}

# Run one cycle. With $1=act, apply the correction; otherwise dry-run (print only).
cycle() {
    local act="${1:-}"
    # Refresh the panel name each cycle (hotplug / Hyprland restart safe).
    PHYS="$(hypr_primary_monitor)"
    if stream_live; then
        [ "$act" = act ] && idle_count=0
        [ "$act" != act ] && log "verdict: STREAM LIVE (session UDP port bound) — would not act"
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
    # Acting loop path: the ANOMALOUS idle state itself must persist for
    # CONFIRM_TICKS consecutive checks. Counting plain idle ticks is not
    # enough: a broken stream detector accumulates "idle" forever, so the
    # confirmation arrives pre-satisfied and the correction fires on the very
    # first tick after a session engages — yanking a live desktop.
    if [ -z "$found" ]; then
        idle_count=0
        return 0
    fi
    idle_count=$((idle_count + 1))
    [ "$idle_count" -lt "$CONFIRM_TICKS" ] && return 0
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
