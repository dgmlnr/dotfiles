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
# The height is derived from the option count so the window never shows a blank
# row. Constants come from style-menu.css: 20px of chrome (2px border + 8px
# inner-box margin, both doubled) and 42px per row (30px line box + 5px entry
# padding + 1px entry margin, the last two doubled). Cross-check: monitor-mode.sh
# shows 3 rows and hardcodes 146 — and 20 + 3*42 is exactly 146.
rows=$(printf '%s\n' "$options" | wc -l)
height=$(( 20 + rows * 42 ))

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
