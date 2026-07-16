#!/usr/bin/env python3
"""Per-workspace taskbar for waybar.

Shows ONLY the apps on the currently active workspace, updating live on Hyprland
events (event-driven via the .socket2 UNIX socket — no polling, no socat).
Run with 'once' to print a single render (for testing); otherwise runs forever.
"""
import socket, os, json, subprocess, sys

SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
RUN = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCK2 = f"{RUN}/hypr/{SIG}/.socket2.sock"

# Pretty names for common app classes; fallback strips reverse-DNS.
NAMES = {
    "com.mitchellh.ghostty": "Ghostty",
    "remotedesktopmanager": "RDM",
    "org.keepassxc.keepassxc": "KeePassXC",
    "org.remmina.remmina": "Remmina",
    "org.pulseaudio.pavucontrol": "Volumen",
}
SEP = "   "

# Nerd Font glyphs per app class. Real themed icons aren't possible in a custom
# waybar module (text/markup only), so we use font glyphs — the name stays as a
# readable fallback if a glyph isn't in the font.
ICONS = {
    "com.mitchellh.ghostty": "",        # terminal
    "remotedesktopmanager": "",         # desktop
    "org.keepassxc.keepassxc": "",      # key
    "org.remmina.remmina": "",          # server
    "firefox": "",                      # firefox
    "org.mozilla.firefox": "",
    "org.pulseaudio.pavucontrol": "",   # volume
}
GENERIC = ""                            # window

def icon(cls):
    return ICONS.get(cls.lower(), GENERIC)

def short(cls):
    k = cls.lower()
    if k in NAMES:
        return NAMES[k]
    part = cls.split(".")[-1]
    return (part[:1].upper() + part[1:]) if part else cls

def hypr(cmd):
    out = subprocess.run(["hyprctl", cmd, "-j"], capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else None

def render():
    try:
        ws = hypr("activeworkspace")["id"]
        clients = hypr("clients") or []
    except Exception:
        print("", flush=True)
        return
    apps = [c.get("class", "") for c in clients
            if c.get("class") and c.get("workspace", {}).get("id") == ws]
    print(SEP.join(f"{icon(c)} {short(c)}" for c in apps), flush=True)

# Events that change WHICH apps are on the active workspace.
TRIGGERS = ("workspace>>", "focusedmon>>", "openwindow>>", "closewindow>>",
            "movewindow>>", "movewindowv2>>")

def main():
    render()  # initial paint
    if len(sys.argv) > 1 and sys.argv[1] == "once":
        return
    if not SIG:
        return
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK2)
    for line in s.makefile("r"):
        if line.startswith(TRIGGERS):
            render()

if __name__ == "__main__":
    main()
