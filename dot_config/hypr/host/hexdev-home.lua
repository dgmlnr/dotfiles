-- ┌─────────────────────────────────────────────────────────────┐
-- │ Host: hexdev-home — laptop                                    │
-- │ Intel i915 (Haswell) · remote-access CLIENT                   │
-- └─────────────────────────────────────────────────────────────┘
--
-- Required at the END of hyprland.lua, so everything here overrides the common
-- core. This machine is the CLIENT of the remote-desktop pair: it runs no VNC
-- server, no Sunshine, no Moonlight headless and no panic-restore. Do not carry
-- any of that over from host/hexdev.lua.

local mainMod = "SUPER"
local home    = os.getenv("HOME")

---------------------
---- MONITORS    ----
---------------------
-- Real monitors on hexdev-home (matched by stable description, not port name).
-- Big external LG E2340 (primary) anchored at the origin; notebook panel to its left.
--
-- ORDER IS LOAD-BEARING: the notebook must be declared FIRST so it reaches
-- -1366x0 before the external claims 0x0. Declared the other way round, the two
-- briefly overlap during startup and focus lands on the wrong output.
-- `preferred` rather than a literal 1366x768@60: the panel advertises exactly one
-- mode, 1366x768@59.99Hz. Hyprland tolerates the rounded request today, but a
-- stricter mode match in a future release would drop the internal display.
hl.monitor({
    output   = "desc:LG Display 0x03E9",
    mode     = "preferred",
    position = "-1366x0",
    scale    = 1,
})

hl.monitor({
    output   = "desc:LG Electronics E2340",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})

------------------------------------
---- WORKSPACE <-> MONITOR BIND ----
------------------------------------
-- Big external = PRIMARY, opens on ws1. Notebook = secondary, ws6-10.
-- When a monitor disconnects, Hyprland relocates its bound workspaces to the
-- remaining active monitor, and moves them back automatically on reconnect.
local EXTERNAL = "desc:LG Electronics E2340"
local NOTEBOOK = "desc:LG Display 0x03E9"

for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = EXTERNAL, default = (i == 1) })
end

for i = 6, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = NOTEBOOK, default = (i == 6) })
end

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
-- NOTE: AQ_NO_MODIFIERS is deliberately absent. The pre-split config carried it
-- over from the work-desktop clone (AMD Polaris, where it works around
-- "GBM: Allocating with modifiers failed"). This GPU is Intel i915, where the
-- flag is not merely unnecessary: it forces linear buffers and gives up
-- compression and tiling. Dropped as part of the per-host split.

---------------------
---- AUTOSTART   ----
---------------------
hl.on("hyprland.start", function()
    -- Lock the session immediately on start. Pairs with LightDM autologin so a reboot
    -- leaves the machine locked at hyprlock instead of dropping to an open desktop.
    -- Unchained (unlike hexdev): there is no headless output to create first.
    hl.exec_cmd("hyprlock")

    -- KWallet (KF6): credential store for KDE apps that don't speak Secret Service.
    -- Kept because the live config on this host starts it; the Smb4K work-share
    -- rationale is really a hexdev concern, so this line can be dropped here once
    -- it is confirmed nothing on the laptop stores credentials in kwalletd6.
    hl.exec_cmd("kwalletd6")

    -- hypridle ENABLED on this host (it is commented out on hexdev on purpose, so
    -- the remote-access server stays reachable and a live stream is never killed by
    -- an idle timeout). A laptop has the opposite requirement: it runs on battery
    -- and travels, so it needs idle-lock and screen-off.
    hl.exec_cmd("hypridle")

    -- Always-on Remote Control Claude session: reachable from the phone via the
    -- claude.ai cloud (no VPN needed). Lives hidden in its own special workspace
    -- (window rule in the common core). Uses bypass permissions per settings.json
    -- defaultMode.
    -- Managed by claude-remote.service (Restart=always) so it self-respawns if it ever
    -- dies. Kicked here (not `systemctl enable`) so the Wayland env is ready first.
    hl.exec_cmd("systemctl --user start claude-remote.service")

    -- Thunderbird: autostart disabled on this host. The window rule in the common
    -- core still sends it to workspace 10 when opened manually.
    -- hl.exec_cmd("thunderbird")
end)

----------------
---- MISC   ----
----------------
-- HOST-ONLY, and the safety net for every manual dpms-off on this box. Hyprland
-- defaults both of these to false, which means a panel blanked with
-- `hyprctl dispatch dpms off` stays blanked: no input wakes it. That used to be
-- survivable because hypridle's idle listener carried an `on-resume` handler that
-- turned dpms back on itself (via the Wayland idle protocol, which does not care
-- about these options). That listener is gone, so without these two there is no
-- wake path at all and a blank is only recoverable over SSH or a blind reboot.
--
-- Deliberately NOT in the common core: hexdev drives a headless Moonlight output
-- and must not have its physical panel woken by remote input.
hl.config({
    misc = {
        mouse_move_enables_dpms = true,
        key_press_enables_dpms  = true,
    },
})

---------------------
---- KEYBINDINGS ----
---------------------
-- Selector de pantallas estilo Win+P: elegí externo / ambos / solo notebook
-- HOST-ONLY: this box is the only one with two real outputs to switch between.
-- SUPER+P is free for it because passthrough is bound to SUPER+SHIFT+Escape in
-- the common core.
hl.bind(mainMod .. " + P",
    hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/monitor-mode.sh"),
    { desc = "Selector de pantallas (Win+P)" })

-- Blank every physical panel on demand (screensaver-style: outputs stay configured
-- and workspaces do not move, unlike SUPER+P which disables an output outright).
-- Wake with any mouse move or keypress, per the misc block above.
--
-- The `sleep 0.5` is required, not cosmetic. The Hyprland wiki explicitly warns
-- against driving dpms straight from a keybind: with key_press_enables_dpms on,
-- releasing M would re-enable dpms the instant the blank landed, so the screens
-- flicker off and back on in one gesture. The delay lets the key release settle
-- first.
hl.bind(mainMod .. " + M",
    hl.dsp.exec_cmd("sleep 0.5 && " .. home .. "/.config/hypr/scripts/idle-dpms.sh off"),
    { desc = "Apagar pantallas" })
