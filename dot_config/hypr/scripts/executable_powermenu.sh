#!/usr/bin/env bash
# Discrete power menu for the waybar power button. Shows actions in wofi.

options="  Bloquear
  Suspender
  Cerrar sesión
  Reiniciar
  Apagar"

# --hide-search plus the compact stylesheet: this is a fixed list of five actions,
# so a search field only adds height and a stray keystroke can dismiss the menu.
# style-menu.css is built for exactly this (its header names the power menu) and
# assumes the field is hidden — pairing it with a visible search leaves dead space.
chosen=$(printf '%s' "$options" | wofi --dmenu --prompt "Power" --hide-search \
    -D image_size=0 --width 220 --height 240 --insensitive -D single_click=true \
    --style "$HOME/.config/wofi/style-menu.css")

case "$chosen" in
    *Bloquear*)       "$HOME/.config/hypr/scripts/lock.sh" ;;
    *Suspender*)      "$HOME/.config/hypr/scripts/suspend.sh" ;;
    *"Cerrar sesión"*) hyprctl dispatch exit ;;
    *Reiniciar*)      systemctl reboot ;;
    *Apagar*)         systemctl poweroff ;;
esac
