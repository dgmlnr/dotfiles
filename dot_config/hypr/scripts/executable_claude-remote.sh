#!/usr/bin/env bash
# Unattended Remote Control Claude session for autostart.
# 1) Mark the home dir as trusted so the workspace-trust dialog never blocks the
#    session (it's interactive, so -p/non-TTY trust-skip doesn't apply here).
# 2) exec into claude --remote-control (registers with the claude.ai cloud).
set -u
CJ="$HOME/.claude.json"

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

# Wait for the claude.ai cloud to be reachable before bridging. Hyprland fires
# this exec-once ~16s into boot, often before the network is up; in that case
# `claude --remote-control` fails its bridge once and never retries, so the
# session never appears on the phone. Poll a TCP connect (PATH-independent bash
# /dev/tcp) and cap the wait so we never hang forever — if it never connects we
# still launch (no worse than today).
for _ in $(seq 1 60); do
  if timeout 5 bash -c 'exec 3<>/dev/tcp/claude.ai/443' 2>/dev/null; then
    break
  fi
  sleep 2
done

exec claude --remote-control
