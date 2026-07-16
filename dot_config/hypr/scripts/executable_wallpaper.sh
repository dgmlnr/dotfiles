#!/usr/bin/env bash
# hyprpaper 0.8.4 silently fails to apply the wallpaper from its own config on
# this setup (daemon runs, listactive stays empty regardless of monitor syntax).
# Apply via IPC once the daemon is up instead. The ',' wildcard targets all
# monitors, so no monitor name is hardcoded.
set -u
WP="$HOME/.config/hypr/wallpapers/escritorio.jpg"

pgrep -x hyprpaper >/dev/null || { hyprpaper & disown; }

for _ in $(seq 1 40); do
  hyprctl hyprpaper wallpaper ",$WP" 2>/dev/null
  active="$(hyprctl hyprpaper listactive 2>/dev/null)"
  [[ "$active" == *"$WP"* ]] && exit 0
  sleep 0.5
done
