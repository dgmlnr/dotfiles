#!/usr/bin/env bash
# hypridle screen-off guard for this AMD Polaris / aquamarine box.
# Blanking a panel (dpms off) while hyprlock is rendering on it crashes hyprlock
# ("atomic drm request: failed to commit ... busy" -> lockscreen app died). So we
# SKIP the idle screen-off while the session is locked; hyprlock stays on a live
# panel. (Trade-off: panel stays on while locked+idle. Worth it vs a crash.)
set -u

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    for d in "$RT"/hypr/*/; do [ -d "$d" ] && sig="$(basename "$d")"; done
    export HYPRLAND_INSTANCE_SIGNATURE="${sig:-}"
fi

case "${1:-}" in
    off) pgrep -x hyprlock >/dev/null || hyprctl dispatch dpms off DP-3 ;;
    on)  hyprctl dispatch dpms on DP-3 ;;
    *)   echo "uso: $0 on|off" >&2; exit 1 ;;
esac
