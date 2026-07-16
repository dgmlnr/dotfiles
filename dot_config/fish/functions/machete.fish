function machete --description 'Chuleta de atajos en la terminal (anda local y por SSH desde Termux)'
    # Mismo cerebro que el machete gráfico (keybinds.py), pero render en terminal
    # con fzf en vez de wofi. No depende de Wayland, asi que funciona por SSH.
    # hyprctl falla por SSH (no hay sesion de Hyprland) y no pasa nada: el script
    # ignora ese error y muestra igual el resto (Ghostty, Nvim, SSH remoto, etc).
    hyprctl binds -j 2>/dev/null \
        | python3 "$HOME/.config/hypr/scripts/keybinds.py" \
        | fzf --prompt 'Buscar atajo > ' --height 90% --layout reverse --info inline
end
