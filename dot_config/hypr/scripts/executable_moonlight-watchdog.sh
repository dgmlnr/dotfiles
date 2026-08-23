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

# Live-stream detection, THREE-VALUED on purpose:
#   0 = a stream is live
#   1 = no stream
#   2 = cannot tell, because the detector itself failed
#
# That third value is the entire point. `ss` printing nothing because no session
# port is bound, and `ss` printing nothing because it is missing or because a
# future iproute2 rejects this filter syntax, are byte-identical at the shell:
# empty stdout either way. Collapsing them into "no stream" is what lets a broken
# detector reach the correction path — during a LIVE session MOON_FLAG is set and
# the panel is dpms-off, which are two of the three anomalies below, so an
# unearned "idle" plus those anomalies tears the desktop off the remote after
# CONFIRM_TICKS. Detecting by port instead of by process name made this detector
# CORRECT; keeping its own failure distinguishable is what makes it HONEST, and
# those are separate properties.
stream_live() {
    local out rc
    out="$(ss -Huan '( sport = :47998 or sport = :47999 or sport = :48000 )' 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "stream detector UNAVAILABLE (ss exit $rc) — cannot tell live from idle"
        return 2
    fi
    [ -n "$out" ]
}

# True while the screen is locked or a lock is starting: do not touch outputs.
locked() { pgrep -x hyprlock >/dev/null 2>&1 || [ -f "$LOCKING" ]; }

# jq predicate that keeps "false" and "could not answer" apart.
#   0 = matched, 1 = did not match, 2 = jq could not evaluate it
# Without that split, a missing jq or a change in hyprctl's JSON shape reads as
# "nothing is wrong" forever, which is indistinguishable from a healthy host.
jq_test() {
    jq -e "$@" >/dev/null 2>&1
    case $? in
        0)   return 0 ;;
        1|4) return 1 ;;   # false / null / no output: a genuine no-match
        *)   return 2 ;;   # usage, compile, or runtime error
    esac
}

# Emit the list of anomalies found on stdout (empty == healthy).
# Returns 0 when the inspection actually RAN, non-zero when it could not.
# Callers must check that status: an inspection that never happened is not a
# clean bill of health, and silently treating it as one turns this watchdog into
# a no-op that still reports itself alive.
anomalies() {
    local mons wss
    mons="$(hyprctl monitors -j 2>/dev/null)" || {
        log "hyprctl monitors failed — anomaly inspection unavailable"; return 1; }
    wss="$(hyprctl workspaces -j 2>/dev/null)" || {
        log "hyprctl workspaces failed — anomaly inspection unavailable"; return 1; }

    # Headless holding a physical workspace (1..10) while idle.
    jq_test --arg hl "$HL" \
        '[.[] | select(.monitor==$hl) | select(.id>0 and .id<=10)] | length>0' <<<"$wss"
    case $? in
        0) echo "headless-holds-physical-ws" ;;
        2) log "jq could not evaluate the workspace filter — inspection unavailable"; return 1 ;;
    esac
    # Panel blanked (dpms off) while idle — the user can't see anything locally.
    # Guarded on a non-empty $PHYS so a failed detection degrades to "can't tell"
    # instead of matching a monitor whose name is the empty string.
    if [ -n "$PHYS" ]; then
        jq_test --arg p "$PHYS" 'any(.[]; .name==$p and (.dpmsStatus==false))' <<<"$mons"
        case $? in
            0) echo "panel-blanked" ;;
            2) log "jq could not evaluate the monitor filter — inspection unavailable"; return 1 ;;
        esac
    fi
    # Stale session flag while no stream is live.
    [ -f "$MOON_FLAG" ] && echo "stale-moon-flag"
    # Explicit, and load-bearing now that the caller reads this status: without it
    # the function returns the test above, so a perfectly healthy host with no
    # flag would report its inspection as having failed.
    return 0
}

# Run one cycle. With $1=act, apply the correction; otherwise dry-run (print only).
cycle() {
    local act="${1:-}" found rc
    # Refresh the panel name each cycle (hotplug / Hyprland restart safe).
    PHYS="$(hypr_primary_monitor)"

    stream_live; rc=$?
    if [ "$rc" -eq 0 ]; then
        [ "$act" = act ] && idle_count=0
        [ "$act" != act ] && log "verdict: STREAM LIVE (session UDP port bound) — would not act"
        return 0
    fi
    if [ "$rc" -eq 2 ]; then
        # Cannot tell. Hold the counter exactly where it is and touch nothing:
        # the whole hazard this guards is that "unknown" looks like "idle" one
        # line later, and "idle" is the branch that tears down a live session.
        log "verdict: UNKNOWN (stream detector unavailable) — holding, no action"
        return 0
    fi

    # Read the status, not just the output: a pipeline here would discard it.
    found="$(anomalies)"; rc=$?
    if [ "$rc" -ne 0 ]; then
        log "verdict: UNKNOWN (anomaly inspection unavailable) — holding, no action"
        return 0
    fi
    found="$(printf '%s' "$found" | paste -sd, -)"
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
