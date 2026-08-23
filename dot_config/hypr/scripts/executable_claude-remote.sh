#!/usr/bin/env bash
# Unattended Remote Control Claude session for autostart.
#
# 1) Mark the home dir as trusted so the workspace-trust dialog never blocks the
#    session (it's interactive, so -p/non-TTY trust-skip doesn't apply here).
# 2) Launch `claude --remote-control` and VERIFY the cloud bridge came up.
#
# Why the verification exists: claude creates the Remote Control session exactly
# once and never retries. A boot-time network race therefore leaves a session
# that is alive but unbridged — the terminal looks perfectly healthy, yet the
# session never appears in the phone app. The only reliable tell is the
# "bridgeSessionId" field, which the session file gains only once the cloud
# session exists.
#
# The previous guard tried to predict readiness with
#   timeout 5 bash -c 'exec 3<>/dev/tcp/claude.ai/443'
# That probe cannot succeed on a network where claude.ai advertises an IPv6
# address that never completes the handshake: the connect only lands after the
# ~8s fallback to IPv4, so a 5s cap always expires. It burned all 60 iterations
# (~7 min) and then launched anyway, with no guarantee at all.
#
# Predicting when the network is ready is guesswork. Verifying the outcome is not.
set -u

CJ="$HOME/.claude.json"
SESSION_DIR="$HOME/.claude/sessions"
BRIDGE_TIMEOUT=90   # seconds to wait for the bridge before forcing a respawn
POLL_INTERVAL=3
DNS_TIMEOUT=60      # seconds to wait for name resolution at boot
MAX_RESPAWNS=5      # consecutive failed boots before we stop respawning
FAIL_FILE="${XDG_RUNTIME_DIR:-/tmp}/claude-remote-bridge-failures"

python3 - "$CJ" "$HOME" <<'PY'
import json, os, sys, tempfile
path, home = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    data = {}
data.setdefault("projects", {}).setdefault(home, {})["hasTrustDialogAccepted"] = True
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".claude.json.")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PY

# Reports success once the session file carries a cloud bridge id.
has_bridge() {
  python3 -c 'import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if data.get("bridgeSessionId") else 1)' "$1" 2>/dev/null
}

# Cheap readiness gate that can actually succeed: name resolution is enough to
# know the network stack is up, and it costs milliseconds once it is.
dns_deadline=$((SECONDS + DNS_TIMEOUT))
while [ "$SECONDS" -lt "$dns_deadline" ]; do
  getent ahosts claude.ai >/dev/null 2>&1 && break
  sleep 2
done

# Watchdog.
#
# LOAD-BEARING INVARIANT: `exec` below replaces this shell with claude while
# keeping the pid, and $$ inside a subshell stays the *script's* pid, not the
# subshell's. Those two facts together are why $$ is both the claude pid and the
# name of the session file claude writes.
#
# If either ever stops holding, this watchdog does not error — it silently polls
# and kills the WRONG pid. Confirm both before changing anything below:
#   bash -c 'echo $$; ( echo $$ )'        # the two numbers must match
#   exec preserves the pid: verify the script's pid becomes the claude pid.
(
  target=$$
  session_file="$SESSION_DIR/$target.json"
  bridge_deadline=$((SECONDS + BRIDGE_TIMEOUT))

  while [ "$SECONDS" -lt "$bridge_deadline" ]; do
    kill -0 "$target" 2>/dev/null || exit 0   # claude exited on its own
    if has_bridge "$session_file"; then
      printf '0\n' > "$FAIL_FILE"             # bridged: clear the failure streak
      exit 0
    fi
    sleep "$POLL_INTERVAL"
  done

  fails=0
  read -r fails < "$FAIL_FILE" 2>/dev/null || fails=0
  case $fails in ''|*[!0-9]*) fails=0 ;; esac
  fails=$((fails + 1))
  printf '%s\n' "$fails" > "$FAIL_FILE"

  # Stop thrashing: after MAX_RESPAWNS consecutive failures, leave the session
  # running unbridged instead of restarting the service forever.
  [ "$fails" -ge "$MAX_RESPAWNS" ] && exit 0

  kill "$target" 2>/dev/null                  # let Restart=always respawn us
) &

exec claude --remote-control
