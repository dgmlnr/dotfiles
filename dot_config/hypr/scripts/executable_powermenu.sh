#!/usr/bin/env bash
# Discrete power menu for the waybar power button. Shows actions in wofi.

options="  Bloquear
  Suspender
  Cerrar sesión
  Reiniciar
  Apagar"

chosen=$(printf '%s' "$options" | wofi --dmenu --prompt "Power" \
    --width 220 --height 250 --insensitive -D single_click=true \
    --style "$HOME/.config/wofi/style.css")

case "$chosen" in
    *Bloquear*)       "$HOME/.config/hypr/scripts/lock.sh" ;;
    *Suspender*)      "$HOME/.config/hypr/scripts/suspend.sh" ;;
    *"Cerrar sesión"*) hyprctl dispatch exit ;;
    *Reiniciar*)      systemctl reboot ;;
    *Apagar*)         systemctl poweroff ;;
esac
