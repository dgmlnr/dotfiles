# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Single source of
truth for every machine (`hexdev`, `hexdev-home`); per-machine differences are
expressed with chezmoi templates keyed on hostname, so the shared 90% never
drifts between machines.

## What is tracked

- **Desktop (Hyprland/Wayland):** `hypr`, `waybar`, `wofi`, `mako`
- **Terminal / shell:** `ghostty`, `fish` (config only), `.bashrc`, `.bash_profile`
- **Dev:** `nvim` (LazyVim config, no `spell/`), `zellij` (config, no `plugins/`),
  `atuin`, `carapace`, `lazysql`, `.gitconfig`, VS Code `settings.json`
- **Theme:** GTK 3/4 `settings.ini`
- **Scripts:** `~/.local/bin/arch-setup-paint-safetynet`
- **Package manifests:** `packages/<hostname>.txt`

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

## Bootstrap a new machine

```sh
# 1. Install chezmoi, then pull and apply this repo (review first with `chezmoi diff`)
sudo pacman -S --needed chezmoi
chezmoi init dgmlnr/dotfiles
chezmoi diff            # inspect every change before it touches your home
chezmoi apply

# 2. Recreate the secrets file (see "Secrets" above)

# 3. Reinstall software from the manifest for this host
sudo pacman -S --needed - < ~/.local/share/chezmoi/packages/hexdev.txt

# 4. Run the local safety-net + Paint setup
arch-setup-paint-safetynet
```

## Per-machine differences

Rename a file to `<name>.tmpl` and branch on hostname, e.g. in a monitor config:

```
{{ if eq .chezmoi.hostname "hexdev" -}}
monitor = DP-1, 2560x1440@144, 0x0, 1
{{- else if eq .chezmoi.hostname "hexdev-home" -}}
monitor = HDMI-A-1, 1920x1080@60, 0x0, 1
{{- end }}
```

Always run `chezmoi diff` before `chezmoi apply` — nothing is ever applied blind.
