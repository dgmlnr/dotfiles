#!/usr/bin/env bash
# vnc-watch — daemon that listens to wayvnc client events and toggles the VNC
# display mode. First client in -> vnc-mode-on; last client out -> vnc-mode-off.
#
# --reconnect keeps the listener alive across wayvnc restarts ONCE wayvncctl is
# attached. But at boot, exec-once can fire this BEFORE wayvnc has created its
# control socket: wayvncctl then exits immediately, the pipe closes, the while
# loop ends, and the watcher dies for good (this is the post-reboot failure where
# VNC connects but never switches to 1920). So we mirror wayvnc-keepalive.sh:
# (a) wait for the socket to exist before attaching, and (b) wrap the whole pipe
# in an outer loop so if the event stream ever ends (socket gone, wayvnc respawn)
# we re-attach instead of dying. jq normalizes the stream to one line per event.
SCRIPTS="$HOME/.config/hypr/scripts"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayvncctl"

while true; do
    # Boot-order guard: don't attach until wayvnc's control socket is up.
    while [ ! -S "$SOCK" ]; do sleep 1; done

    wayvncctl -j --reconnect event-receive \
      | jq --unbuffered -r '"\(.method) \(.params["connection_count"] // -1)"' \
      | while read -r method count; do
            case "$method" in
                client-connected)
                    [ "$count" = "1" ] && "$SCRIPTS/vnc-mode-on.sh"
                    ;;
                client-disconnected)
                    [ "$count" = "0" ] && "$SCRIPTS/vnc-mode-off.sh"
                    ;;
            esac
        done

    # Stream ended (socket vanished / wayvnc restarting). Pause, then re-attach.
    sleep 2
done
