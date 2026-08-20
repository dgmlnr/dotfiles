# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Single source of
truth for every machine (`hexdev`, `hexdev-home`); per-machine differences are
expressed with chezmoi templates keyed on hostname, so the shared 90% never
drifts between machines.

## What is tracked

- **Desktop (Hyprland/Wayland):** `hypr`, `waybar`, `wofi`, `mako`
- **Terminal / shell:** `ghostty`, `fish` (config only), `.bashrc`, `.bash_profile`
- **Dev:** `nvim` (LazyVim config, no `spell/`), `zellij` (config, no `plugins/`),
  `atuin`, `carapace`, `.gitconfig` (+ `.gitconfig-work`), VS Code `settings.json`
- **Theme:** GTK 3/4 `settings.ini`
- **Scripts:** `~/.local/bin/arch-setup-paint-safetynet`
- **Package manifests:** `packages/<hostname>.txt` + `packages/<hostname>-aur.txt`

Regenerable state (fish completions, nvim spell files, zellij plugins) and all
secrets are deliberately excluded — see `.chezmoiignore`.

## Secrets — never committed

Machine-local secrets live in `~/.config/shell/secrets.sh` (chmod 600), which
`.bashrc` sources if present. This file is **never** tracked by chezmoi. On a new
machine, create it by hand:

```sh
mkdir -p ~/.config/shell
printf 'export ENGRAM_CLOUD_TOKEN=%s\n' 'YOUR_TOKEN_HERE' > ~/.config/shell/secrets.sh
chmod 600 ~/.config/shell/secrets.sh
```

The `gitea-cred-update` helper reads its target from that same file:

```sh
export GITEA_HOST=gitea.example.com
export GITEA_USER=yourname
export GITEA_PROBE_REPO=any-repo   # only used to verify that auth works
export GITEA_PEER=other-hostname   # optional, ssh alias of the second machine
```

## Work identity — never committed

`~/.gitconfig-work` holds a second git identity, applied by `includeIf` to repos
under `~/repos/gitea/`. It is machine-local and never tracked. Git ignores a
missing include, so a machine without it simply uses the default identity:

```sh
cat > ~/.gitconfig-work <<'EOF'
[user]
	name = yourname
	email = you@example.com
EOF
```

## Bootstrap a new machine

```sh
# 1. Install chezmoi, then pull and apply this repo (review first with `chezmoi diff`)
sudo pacman -S --needed chezmoi
chezmoi init dgmlnr/dotfiles
chezmoi diff            # inspect every change before it touches your home
chezmoi apply

# 2. Recreate the secrets file (see "Secrets" above)

# 3. Reinstall software from the manifests for this host ($HOST = hexdev | hexdev-home)
sudo pacman -S --needed - < ~/.local/share/chezmoi/packages/$HOST.txt
yay  -S --needed - < ~/.local/share/chezmoi/packages/$HOST-aur.txt

# 4. Run the local safety-net + Paint setup
arch-setup-paint-safetynet
```

For a machine whose hostname is neither `hexdev` nor `hexdev-home`, add
`dot_config/hypr/host/<hostname>.conf` and `packages/<hostname>{,-aur}.txt`
*before* applying — `hyprland.conf` sources its host file unconditionally and
will error on a missing one.

## Per-machine differences

Three mechanisms, in order of preference.

### 1. Hyprland: one common core + one host file

`dot_config/hypr/hyprland.conf.tmpl` holds everything shared. Its only templated
line is the last one:

```
source = ~/.config/hypr/host/{{ .chezmoi.hostname }}.conf
```

Host files are plain (non-template) config, sourced **last** so they override the
common core:

| File | Machine |
|---|---|
| `dot_config/hypr/host/hexdev.conf` | work desktop, AMD Polaris, remote-access **server** (wayvnc + Sunshine/Moonlight) |
| `dot_config/hypr/host/hexdev-home.conf` | laptop, Intel i915, remote-access **client** |

Both host files are materialised on **both** machines; only the `source =` line
picks which one is read. Put a setting in a host file only when it is false or
harmful elsewhere (e.g. `env = AQ_NO_MODIFIERS,1` fixes AMD Polaris and would
cost the laptop's i915 compression and tiling).

### 2. `.chezmoiignore` is a template

It branches on hostname to keep host-irrelevant files out of `$HOME` entirely.
Today that is the seven remote-access **server** scripts, which exist only for
`hexdev`:

```
{{ if ne .chezmoi.hostname "hexdev" -}}
.config/hypr/scripts/vnc-mode-on.sh
...
{{- end }}
```

`ne "hexdev"` (rather than an equality test against the laptop) means any *new*
host is a client by default. The block matches `.config/hypr/scripts/` paths
only — it must never catch `.config/hypr/host/*.conf`.

Verify with `chezmoi ignored`.

### 3. Any other file

Rename it to `<name>.tmpl` and branch on `.chezmoi.hostname` inline. Prefer
mechanisms 1 and 2; inline conditionals scattered through a long file are the
thing this layout exists to avoid.

Always run `chezmoi diff` before `chezmoi apply` — nothing is ever applied blind.
