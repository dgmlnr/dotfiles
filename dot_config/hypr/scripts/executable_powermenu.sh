#!/usr/bin/env bash
# Discrete power menu for the waybar power button. Shows actions in wofi.

options="  Bloquear
  Suspender
  Cerrar sesión
  Reiniciar
  Apagar"

# --hide-search plus the compact stylesheet: this is a fixed list of actions, so a
# search field only adds height and a stray keystroke can dismiss the menu.
# style-menu.css is built for exactly this (its header names the power menu) and
# assumes the field is hidden — pairing it with a visible search leaves dead space.
#
# Height is computed from the row count. The constants below were MEASURED, not
# derived from the stylesheet: rendering the same menu at 3 and 5 rows and reading
# the layer surface back with `hyprctl layers` gave 108px and 180px, so a row is
# exactly 36px and --lines reserves nothing for chrome. CHROME covers what --lines
# ignores: the 2px border top and bottom plus the inner-box margins from
# style-menu.css (8px top, 14px bottom — the bottom is deliberately larger so the
# last action does not sit against the rounded border).
#
# Do not switch this back to --lines: it sizes to content exactly, so the margins
# have no room and eat the last row instead of padding it.
ROW_PX=36
CHROME_PX=26
rows=$(printf '%s\n' "$options" | wc -l)
height=$(( rows * ROW_PX + CHROME_PX ))

chosen=$(printf '%s' "$options" | wofi --dmenu --prompt "Power" --hide-search \
    -D image_size=0 --width 220 --height "$height" --insensitive -D single_click=true \
    --style "$HOME/.config/wofi/style-menu.css")

case "$chosen" in
    *Bloquear*)       "$HOME/.config/hypr/scripts/lock.sh" ;;
    *Suspender*)      "$HOME/.config/hypr/scripts/suspend.sh" ;;
    *"Cerrar sesión"*) hyprctl dispatch exit ;;
    *Reiniciar*)      systemctl reboot ;;
    *Apagar*)         systemctl poweroff ;;
esac
