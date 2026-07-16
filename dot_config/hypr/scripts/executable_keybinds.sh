#!/usr/bin/env bash
# On-screen keybind cheatsheet across environments. Aggregates Hyprland binds
# (live via hyprctl) + Ghostty keybinds (config), each tagged [Hyprland]/[Ghostty]
# so you can filter by environment (type "ghostty") or by intent (type "volumen").
# Rendering logic lives in keybinds.py (single source of truth, maintainable).
#
# Al elegir una fila, copia el comando/atajo al portapapeles (wl-copy) y avisa.

selected="$(hyprctl binds -j \
  | python3 "$HOME/.config/hypr/scripts/keybinds.py" \
  | wofi --dmenu --prompt "Buscar atajo (o entorno)" --width 820 --height 640 --insensitive)"

# Sin selección (Esc / cierre): no hacemos nada.
[ -z "$selected" ] && exit 0

# Las filas son de ancho fijo: env(11) + espacio(1) + desc(46) + 2 espacios = 60.
# El comando/atajo es todo lo que viene a partir del índice 60.
cmd="${selected:60}"
# Recortar espacios sobrantes al final, por las dudas.
cmd="${cmd%"${cmd##*[![:space:]]}"}"

printf '%s' "$cmd" | wl-copy
notify-send "Machete" "Copiado al portapapeles:\n$cmd" 2>/dev/null || true
