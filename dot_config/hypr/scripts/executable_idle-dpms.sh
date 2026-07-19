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
        pgrep -x hyprlock >/dev/null && exit 0
        for m in $MONS; do hyprctl dispatch dpms off "$m"; done
        ;;
    on)
        for m in $MONS; do hyprctl dispatch dpms on "$m"; done
        ;;
    *)  echo "uso: $0 on|off" >&2; exit 1 ;;
esac
