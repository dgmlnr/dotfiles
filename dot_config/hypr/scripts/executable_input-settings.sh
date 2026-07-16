#!/usr/bin/env bash
# Configuracion de entrada (teclado y mouse) para Hyprland.
# Menu wofi que aplica en vivo con hyprctl y persiste en hyprland.conf.

CONF="$HOME/.config/hypr/hyprland.conf"
menu() { wofi --dmenu --insensitive -p "$1"; }
notify() { command -v notify-send >/dev/null && notify-send "$1" "$2"; }

# Leer una opcion en vivo desde hyprctl (campo str/float/int).
get() { hyprctl getoption "$1" -j 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('$2',''))"; }

# Persistir 'clave = valor' en hyprland.conf conservando la indentacion.
persist() {
    python3 - "$CONF" "$1" "$2" <<'PY'
import re, sys
conf, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(conf, encoding="utf-8").read()
pat = re.compile(r'(?m)^(\s*' + re.escape(key) + r'\s*=\s*).*$')
if pat.search(s):
    s = pat.sub(lambda m: m.group(1) + val, s, count=1)
    open(conf, "w", encoding="utf-8").write(s)
PY
}

cur_layout=$(get input:kb_layout str)
cur_sens=$(get input:sensitivity float)
cur_nat=$(get input:touchpad:natural_scroll int)
[ "$cur_nat" = "1" ] && nat_lbl="activado" || nat_lbl="desactivado"
cur_sens=$(printf '%.2f' "${cur_sens:-0}" 2>/dev/null || echo 0)

sel=$(printf '%s\n' \
    "Teclado:  ${cur_layout:-?}" \
    "Scroll natural:  ${nat_lbl}" \
    "Sensibilidad mouse:  ${cur_sens}" \
    | menu "Entrada")
[ -z "$sel" ] && exit 0

case "$sel" in
    Teclado:*)
        lay=$(printf '%s\n' \
            "latam   (espanol latino)" \
            "es      (espanol Espana)" \
            "us      (ingles EE.UU.)" \
            | menu "Distribucion de teclado")
        [ -z "$lay" ] && exit 0
        code="${lay%% *}"
        hyprctl keyword input:kb_layout "$code" >/dev/null
        persist kb_layout "$code"
        notify "Teclado" "Distribucion: $code"
        ;;
    Scroll*)
        if [ "$cur_nat" = "1" ]; then new=false; else new=true; fi
        hyprctl keyword input:touchpad:natural_scroll "$new" >/dev/null
        persist natural_scroll "$new"
        notify "Mouse / Touchpad" "Scroll natural: $new"
        ;;
    Sensibilidad*)
        val=$(printf '%s\n' "-0.5" "-0.25" "0" "0.25" "0.5" "0.75" "1.0" \
            | menu "Sensibilidad (-1 a 1)")
        [ -z "$val" ] && exit 0
        hyprctl keyword input:sensitivity "$val" >/dev/null
        persist sensitivity "$val"
        notify "Mouse" "Sensibilidad: $val"
        ;;
esac
