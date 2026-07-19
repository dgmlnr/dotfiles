#!/usr/bin/env bash
# SUPER+P — display-mode selector, Win+P style. Pick which monitor(s) are active;
# Hyprland relocates the bound workspaces on its own. No daemon, no polling.
#
# The monitor identifiers and their geometry are NOT written here. They are parsed
# at runtime out of the per-host Hyprland file that already declares them:
#
#     ~/.config/hypr/host/<hostname>.conf
#
# Why: this script used to keep its own copy of the descriptions and the exact
# geometry (BIG_DESC/NB_DESC/BIG_ON/NB_LEFT/NB_ORIGIN). Once hyprland.conf was split
# into a common core plus a per-host file, that copy became a second source of truth
# that nothing kept in sync — and the drift fails SILENTLY, because
# `hyprctl keyword monitor` against an identifier that does not match any output is
# a no-op that still returns success. The user would get the "Pantallas" notification
# and no change on screen. Parsing the host file removes the second copy entirely.
set -u

# shellcheck source=lib-monitors.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-monitors.sh"
hypr_ensure_signature   # so hyprctl also works if this is ever run outside the session

CONF="$HOME/.config/hypr/host/${HOSTNAME:-$(hostname)}.conf"

die() {
    notify-send -u critical -t 4000 "Pantallas" "$1" 2>/dev/null || true
    echo "monitor-mode: $1" >&2
    exit 1
}

[ -r "$CONF" ] || die "No encuentro el archivo del host: $CONF"

# Pull every real `monitor = <id>, <res>, <pos>, <scale>` declaration out of the host
# file as pipe-separated records. Skipped on purpose:
#   - comment lines, and trailing `# ...` comments on a live line;
#   - the common core's catch-all `monitor = , preferred, auto, 1` (empty identifier);
#   - headless outputs such as hexdev's "moonlight", which are virtual and must never
#     appear in a physical display-mode menu.
parse_monitors() {
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*monitor[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*#.*$/, "")
            n = split($0, f, /[[:space:]]*,[[:space:]]*/)
            if (n < 3) next
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[1])
            if (f[1] == "" || f[1] == "moonlight") next
            printf "%s|%s|%s|%s\n", f[1], f[2], f[3], (n >= 4 ? f[4] : "1")
        }
    ' "$CONF"
}

IDS=() RESS=() POSS=() SCALES=()
while IFS='|' read -r id res pos scale; do
    [ -z "$id" ] && continue
    IDS+=("$id"); RESS+=("$res"); POSS+=("$pos"); SCALES+=("$scale")
done < <(parse_monitors)

[ "${#IDS[@]}" -ge 2 ] || die "Este equipo declara ${#IDS[@]} monitor(es) en $(basename "$CONF"); el selector necesita 2."

# PRIMARY = the one the host file anchors at the origin (0x0). Both host files pin
# their primary there deliberately, and lib-monitors.sh uses the same convention to
# detect the primary output at runtime — one rule, applied consistently.
PRIMARY=-1
for i in "${!IDS[@]}"; do
    [ "${POSS[$i]}" = "0x0" ] && { PRIMARY=$i; break; }
done
[ "$PRIMARY" -ge 0 ] || die "Ningún monitor está anclado en 0x0 en $(basename "$CONF")."

# SECONDARY = the first monitor that is not the primary.
SECONDARY=-1
for i in "${!IDS[@]}"; do
    [ "$i" -ne "$PRIMARY" ] && { SECONDARY=$i; break; }
done

# Rebuild the `hyprctl keyword monitor` argument strings from the parsed geometry.
spec()        { printf '%s,%s,%s,%s' "${IDS[$1]}" "${RESS[$1]}" "${POSS[$1]}" "${SCALES[$1]}"; }
spec_origin() { printf '%s,%s,0x0,%s'  "${IDS[$1]}" "${RESS[$1]}" "${SCALES[$1]}"; }

PRIMARY_ON="$(spec "$PRIMARY")"          # primary in its declared place (the origin)
SECONDARY_AT="$(spec "$SECONDARY")"      # secondary in its declared place (left of it)
SECONDARY_ORIGIN="$(spec_origin "$SECONDARY")"   # secondary alone -> it takes the origin

OPT_BOTH="󰍺  Ambos (externo + notebook)"
OPT_EXT="󰍹  Solo monitor externo"
OPT_NB="󰌢  Solo notebook"

choice=$(printf '%s\n' "$OPT_BOTH" "$OPT_EXT" "$OPT_NB" \
  | wofi --dmenu --hide-search -D image_size=0 --width 500 --height 146 --insensitive \
    --style "$HOME/.config/wofi/style-menu.css")

[ -z "$choice" ] && exit 0   # cancelled

case "$choice" in
    *Ambos*)
        hyprctl keyword monitor "$SECONDARY_AT"   # secondary (off-origin) first, so the
        hyprctl keyword monitor "$PRIMARY_ON"     # primary can take 0x0 with no overlap
        msg="Ambos monitores" ;;
    *"monitor externo"*)
        focused=$(hyprctl activeworkspace -j | jq -r '.id')
        # Park the secondary at its off-origin slot before the primary takes 0x0, so
        # the two never overlap while both are briefly on (Hyprland warns and misplaces
        # focus on overlap). Then move the secondary's live workspaces onto the primary
        # while both are still up (no relocation race), and only then disable it.
        hyprctl keyword monitor "$SECONDARY_AT"
        hyprctl keyword monitor "$PRIMARY_ON"
        sec_name=$(hyprctl monitors -j \
          | jq -r --arg d "${IDS[$SECONDARY]#desc:}" '.[] | select(.description | startswith($d)) | .name')
        for ws in $(hyprctl workspaces -j \
          | jq -r --arg m "$sec_name" '.[] | select(.monitor == $m and .id > 0) | .id'); do
            hyprctl dispatch moveworkspacetomonitor "$ws ${IDS[$PRIMARY]}"
        done
        hyprctl keyword monitor "${IDS[$SECONDARY]},disable"
        hyprctl dispatch workspace "$focused"   # land where the user was, not an empty ws
        msg="Solo monitor externo" ;;
    *"Solo notebook"*)
        hyprctl keyword monitor "${IDS[$PRIMARY]},disable"
        hyprctl keyword monitor "$SECONDARY_ORIGIN"
        msg="Solo notebook" ;;
    *)
        exit 0 ;;
esac

# Waybar binds its bars to the outputs present at launch, so a monitor topology
# change can leave it without a surface on the surviving display. Restart it (via
# hyprctl so Hyprland owns the process) once the new layout has settled.
killall waybar 2>/dev/null || true
sleep 0.3
hyprctl dispatch exec waybar

notify-send -t 2000 "Pantallas" "$msg" 2>/dev/null || true
