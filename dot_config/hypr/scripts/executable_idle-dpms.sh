#!/usr/bin/env bash
# hypridle screen-off guard for this AMD Polaris / aquamarine box.
# Blanking a panel (dpms off) while hyprlock is rendering on it crashes hyprlock
# ("atomic drm request: failed to commit ... busy" -> lockscreen app died). So we
# SKIP the idle screen-off while the session is locked; hyprlock stays on a live
# panel. (Trade-off: panel stays on while locked+idle. Worth it vs a crash.)
set -u

# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"

# Every real output, detected at runtime. hypridle only runs on the laptop (it is
# commented out on hexdev on purpose so the remote box stays reachable), and the
# laptop has TWO panels — blanking just the primary would leave the notebook lit.
# Headless outputs are excluded, so this can never blank hexdev's moonlight output
# and kill a live stream the way a bare `dpms off` with no argument would.
MONS="$(hypr_physical_monitors)"
if [ -z "$MONS" ]; then
    echo "idle-dpms: no physical monitor found" >&2
    exit 1
fi

case "${1:-}" in
    off)
        # Skip the idle blank entirely while locked (see the header): hyprlock
        # rendering on a panel we blank underneath it is what crashes it.
        #
        # Two independent signals decide this, because a single silent detector
        # getting it wrong produces exactly the crash the guard exists to prevent.
        # `pgrep -x` matches on process name and quietly stops matching if the
        # binary is ever renamed or wrapped; lock.sh's marker file is present for
        # the whole lock (it touches the file, then hyprlock blocks, and an EXIT
        # trap clears it). Either signal alone is enough to take the safe branch.
        LOCK_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprlock-starting"

        # If the detector itself cannot run we do not know whether we are locked.
        # Blanking while locked crashes hyprlock; leaving the panel lit costs
        # nothing but a lit panel. Fail closed, and say so rather than blanking.
        if ! command -v pgrep >/dev/null 2>&1; then
            echo "idle-dpms: pgrep unavailable, cannot tell if locked - not blanking" >&2
            exit 0
        fi

        if pgrep -x hyprlock >/dev/null || [ -f "$LOCK_FLAG" ]; then
            exit 0
        fi
        for m in $MONS; do hyprctl dispatch dpms off "$m"; done
        ;;
    on)
        for m in $MONS; do hyprctl dispatch dpms on "$m"; done
        ;;
    *)  echo "uso: $0 on|off" >&2; exit 1 ;;
esac
