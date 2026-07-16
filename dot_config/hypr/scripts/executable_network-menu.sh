#!/usr/bin/env bash
# General NetworkManager menu via wofi (wired + wifi + VPN).
# Left-click target for the Waybar `network` module.

menu() { wofi --dmenu --insensitive -p "$1"; }

items=""

# Active connections -> offer to disconnect.
while IFS=: read -r name type dev; do
    [ -z "$name" ] && continue
    case "$type" in loopback|bridge|tun|*tun*) continue ;; esac
    items+="Desconectar  ${name}  (${type} / ${dev})"$'\n'
done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)

# Saved profiles not currently active -> offer to connect.
active=$(nmcli -t -f NAME connection show --active 2>/dev/null)
while IFS=: read -r name type; do
    [ -z "$name" ] && continue
    case "$type" in loopback|bridge|tun|*tun*) continue ;; esac
    printf '%s\n' "$active" | awk -v s="$name" '$0==s{f=1} END{exit !f}' && continue
    items+="Conectar  ${name}  (${type})"$'\n'
done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)

# WiFi networks in range (only if the radio is on).
wifi_on=$(nmcli -t -f WIFI g 2>/dev/null)
if [ "$wifi_on" = "enabled" ]; then
    nmcli device wifi rescan >/dev/null 2>&1
    sleep 1
    while IFS=: read -r inuse ssid signal sec; do
        [ -z "$ssid" ] && continue
        items+="WiFi  ${ssid}  (${signal}% / ${sec:-abierta})"$'\n'
    done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | awk -F: '!seen[$2]++')
    toggle="Desactivar WiFi"
else
    toggle="Activar WiFi"
fi

items+="${toggle}"$'\n'
items+="Editor de red"

sel=$(printf '%s' "$items" | menu "Red")
[ -z "$sel" ] && exit 0

# Exact-match actions first.
case "$sel" in
    "Activar WiFi")    nmcli radio wifi on;  exit 0 ;;
    "Desactivar WiFi") nmcli radio wifi off; exit 0 ;;
    "Editor de red")   nm-connection-editor & exit 0 ;;
esac

# Prefixed actions: "<verb>  <name>  (<meta>)".
verb="${sel%%  *}"
rest="${sel#*  }"
name="${rest%%  (*}"
[ -z "$name" ] && exit 0

case "$verb" in
    "Desconectar")
        nmcli connection down id "$name"
        ;;
    "Conectar")
        nmcli connection up id "$name"
        ;;
    "WiFi")
        # Known network -> bring it up; otherwise try open, then prompt password.
        known=$(nmcli -t -f NAME connection show | awk -v s="$name" '$0==s{print;exit}')
        if [ -n "$known" ]; then
            nmcli connection up id "$name"
        elif ! nmcli device wifi connect "$name" >/dev/null 2>&1; then
            pass=$(printf '' | wofi --dmenu --password -p "Contrasena de $name")
            [ -z "$pass" ] && exit 0
            nmcli device wifi connect "$name" password "$pass"
        fi
        ;;
esac
