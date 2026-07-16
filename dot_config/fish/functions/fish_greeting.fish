function fish_greeting --description 'Intro animada hex-dev (C5: solo en terminal fresca)'
    # C5 — animar SOLO en una terminal "fresca":
    #   saltar shells no interactivas, tmux, sesiones SSH y subshells anidadas.
    status is-interactive; or return
    set -q TMUX; and return            # dentro de tmux
    set -q SSH_TTY; and return         # sesión SSH
    set -q SSH_CONNECTION; and return
    set -q HEXDEV_GREETED; and return  # ya saludó en un shell padre de este árbol
    set -gx HEXDEV_GREETED 1           # marcar para los hijos (subshells heredan y saltan)
    python3 $HOME/.config/fish/hexdev-intro.py
end
