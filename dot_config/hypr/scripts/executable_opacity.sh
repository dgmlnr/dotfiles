#!/usr/bin/env bash
# Live-tune global window opacity. $1 = step (e.g. 0.05 or -0.05).
# Keeps the current value in a state file (hyprctl keyword changes aren't
# queryable cheaply), clamps to a sane range, and shows the value via mako.
# NOTE: hyprctl keyword is NOT persistent — once you settle on a value, bake it
# into the `decoration { active_opacity / inactive_opacity }` block in
# hyprland.conf so it survives reload/reboot.
set -u
STATE="$HOME/.cache/hypr-active-opacity"
STEP="${1:?usage: opacity.sh <+/-step>}"

cur="0.92"
[[ -r "$STATE" ]] && cur="$(<"$STATE")"

new="$(awk -v c="$cur" -v s="$STEP" 'BEGIN{n=c+s; if(n>1)n=1; if(n<0.40)n=0.40; printf "%.2f", n}')"
inact="$(awk -v n="$new" 'BEGIN{m=n-0.10; if(m<0.30)m=0.30; printf "%.2f", m}')"

printf '%s' "$new" > "$STATE"
hyprctl keyword decoration:active_opacity   "$new"   >/dev/null
hyprctl keyword decoration:inactive_opacity "$inact" >/dev/null
notify-send -t 900 -h string:x-canonical-private-synchronous:opacity \
  "Opacidad ventanas" "activa $new · inactiva $inact" 2>/dev/null
