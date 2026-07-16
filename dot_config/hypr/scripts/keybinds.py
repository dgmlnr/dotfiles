#!/usr/bin/env python3
"""Render a unified, searchable keybind cheatsheet from multiple environments.
Reads Hyprland binds (hyprctl binds -j on stdin) + Ghostty keybinds (config file).
Every row is tagged with its environment ([Hyprland] / [Ghostty]) so you can
filter by typing the environment name in wofi, and rows group by environment.
"""
import json, sys, re, os

MODS = {1: "SHIFT", 4: "CTRL", 8: "ALT", 64: "SUPER"}
COLLAPSE = {"workspace", "movetoworkspace"}  # numeric series → one row
MOUSE = {  # nombres crudos de Hyprland → texto legible en la columna del atajo
    "mouse:272": "clic izq", "mouse:273": "clic der",
    "mouse_up": "rueda ↑", "mouse_down": "rueda ↓",
}
MEDIA = {  # teclas multimedia dedicadas (XF86…) → su función real
    "XF86AudioRaiseVolume": "Vol +", "XF86AudioLowerVolume": "Vol −",
    "XF86AudioMute": "Mute",
    "XF86MonBrightnessUp": "Brillo +", "XF86MonBrightnessDown": "Brillo −",
}

def mod_str(mask):
    return "+".join(name for bit, name in sorted(MODS.items()) if mask & bit)

def row(env, desc, combo):
    return f"{env:<11} {desc:<46.46}  {combo}"

rows = set()

# ---- Hyprland (stdin: hyprctl binds -j) ----
try:
    binds = json.load(sys.stdin)
except Exception:
    binds = []
seen = set()
for b in binds:
    disp = b.get("dispatcher", "")
    arg = b.get("arg", "")
    mods = mod_str(b.get("modmask", 0))
    raw_key = b.get("key", "")
    # XF86… sin mapear cae al fallback (le saca el prefijo críptico)
    key = MOUSE.get(raw_key) or MEDIA.get(raw_key) or \
        (raw_key[4:] if raw_key.startswith("XF86") else raw_key)
    desc = b.get("description")
    if not desc and disp == "exec":
        continue  # exec sin descripción = comando crudo, ruido en un cheatsheet
    desc = desc or (disp + " " + arg).strip()
    if disp in COLLAPSE and arg.isdigit():
        gk = (disp, b.get("modmask", 0))
        if gk in seen:
            continue
        seen.add(gk)
        base = re.sub(r"\s*\d+\s*$", "", desc) + " (1-10)"
        rows.add(row("[Hyprland]", base, "+".join(filter(None, [mods, "1…0"]))))
        continue
    combo = "+".join(filter(None, [mods, key]))
    if combo and desc:
        rows.add(row("[Hyprland]", desc, combo))

# ---- Ghostty (config keybind lines) ----
GDESC = {
    "new_tab": "Nueva tab", "close_tab": "Cerrar tab",
    "new_split": "Nuevo split", "goto_split": "Ir al split", "close_surface": "Cerrar split",
    "resize_split": "Redimensionar split", "clear_screen": "Limpiar pantalla",
    "copy_to_clipboard": "Copiar", "paste_from_clipboard": "Pegar",
    "write_screen_file": "Volcar pantalla a archivo",
}
DIRS = {"right": "a la derecha", "left": "a la izquierda", "up": "arriba", "down": "abajo"}
cfg = os.path.expanduser("~/.config/ghostty/config")
if os.path.exists(cfg):
    for line in open(cfg, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line.startswith("keybind"):
            continue
        m = re.match(r"keybind\s*=\s*(.+?)=(.+)", line)
        if not m:
            continue
        combo, action = m.group(1).strip(), m.group(2).strip()
        base = action.split(":")[0]
        if base in ("unbind", "text") or action == "unbind":
            continue
        if "cmd" in combo.lower():   # Mac-only default, dead on Linux
            continue
        desc = GDESC.get(base, base)
        rest = action.split(":", 1)[1].split(",")[0] if ":" in action else ""
        if rest in DIRS:
            desc = f"{desc} {DIRS[rest]}"
        rows.add(row("[Ghostty]", desc, combo.upper()))

# ---- Lazygit (curated defaults; the app has no readable keybind file) ----
# Panel-prefixed because the same key means different things per panel
# (e.g. d = discard in Files, delete in Commits, drop in Stash).
LAZYGIT = [
    ("Global: saltar a panel por número", "1…5"),
    ("Global: siguiente panel", "Tab"),
    ("Global: bajar / subir en la lista", "j / k"),
    ("Global: ayuda del panel actual", "?"),
    ("Global: buscar / filtrar", "/"),
    ("Global: menú de acciones del panel", "x"),
    ("Global: cancelar / volver", "Esc"),
    ("Global: salir", "q"),
    ("Global: pull", "p"),
    ("Global: push", "SHIFT+P"),
    ("Files: stage / unstage archivo", "espacio"),
    ("Files: stage / unstage todo", "a"),
    ("Files: commit", "c"),
    ("Files: amend al último commit", "SHIFT+A"),
    ("Files: entrar al archivo (stagear líneas)", "Enter"),
    ("Files: descartar cambios", "d"),
    ("Files: stash de los cambios", "s"),
    ("Commits: reword (editar mensaje)", "r"),
    ("Commits: squash hacia abajo", "s"),
    ("Commits: fixup hacia abajo", "f"),
    ("Commits: borrar commit", "d"),
    ("Commits: reset a este commit", "g"),
    ("Branches: checkout a la rama", "espacio"),
    ("Branches: nueva rama", "n"),
    ("Branches: merge a la rama actual", "SHIFT+M"),
    ("Branches: rebase sobre la rama", "r"),
    ("Stash: aplicar (pop)", "espacio"),
    ("Stash: dropear", "d"),
]
for desc, key in LAZYGIT:
    rows.add(row("[Lazygit]", desc, key))

# ---- SQL Server local (helper fish functions) ----
SQL = [
    ("Levantar el SQL Server local", "sqlup"),
    ("Bajar el SQL Server local (libera RAM)", "sqldown"),
    ("Estado del SQL Server local", "sqlstatus"),
]
for desc, key in SQL:
    rows.add(row("[SQL]", desc, key))

# ---- Docker (comandos frecuentes) ----
DOCKER = [
    ("Listar containers corriendo", "docker ps"),
    ("Listar TODOS los containers (incl. parados)", "docker ps -a"),
    ("Levantar servicio en background", "docker compose up -d"),
    ("Bajar servicio (para; conserva el container)", "docker compose stop"),
    ("Eliminar container (conserva volúmenes)", "docker compose down"),
    ("Ver logs en vivo de un container", "docker logs -f <nombre>"),
    ("Abrir shell dentro de un container", "docker exec -it <nombre> bash"),
    ("Listar imágenes descargadas", "docker images"),
    ("Listar volúmenes (datos persistentes)", "docker volume ls"),
    ("Uso de CPU/RAM por container en vivo", "docker stats"),
    ("Limpiar imágenes/containers sin usar", "docker system prune"),
]
for desc, key in DOCKER:
    rows.add(row("[Docker]", desc, key))

# ---- Lazysql (TUI de bases de datos) ----
LAZYSQL = [
    ("Nav: moverse en árbol / lista", "↑/↓ (o j/k)"),
    ("Nav: abrir tabla (ver registros)", "Enter"),
    ("Nav: ir a panel árbol / tabla", "H / L"),
    ("Nav: buscar / filtrar", "/"),
    ("Nav: refrescar", "R"),
    ("Nav: toggle sidebar", "S"),
    ("Nav: ayuda (todas las teclas)", "?"),
    ("Nav: salir", "q"),
    ("Editor: abrir editor SQL", "Ctrl+E"),
    ("Editor: ejecutar query", "Ctrl+R"),
    ("Editor: guardar cambios", "Ctrl+S"),
    ("Datos: moverse entre celdas", "Tab / Shift+Tab"),
    ("Datos: página siguiente / anterior", "> / <"),
    ("Datos: copiar celda", "y"),
    ("Datos: editar celda", "c"),
    ("Datos: insertar / borrar fila", "o / d"),
    ("Datos: ordenar asc / desc", "K / J"),
    ("Datos: exportar a CSV", "E"),
    ("Tabs: siguiente / anterior", "] / ["),
    ("Tabs: cerrar", "X"),
    ("Vista: registros / columnas", "1 / 2"),
]
for desc, key in LAZYSQL:
    rows.add(row("[Lazysql]", desc, key))

# ---- Paquetes (pacman + yay): instalar, sacar, recordar ----
# El sistema ya lleva el historial por vos: /var/log/pacman.log es tu memoria.
PAQUETES = [
    ("Buscar un paquete YA instalado por nombre", "pacman -Qs <texto>"),
    ("Ver cómo/cuándo instalaste algo (historial)", "rg <paquete> /var/log/pacman.log"),
    ("Listar solo lo que instalaste vos (tus apps)", "pacman -Qqe"),
    ("Ver info/detalle de un paquete instalado", "pacman -Qi <paquete>"),
    ("Buscar algo para instalar (repos + AUR)", "yay -Ss <texto>"),
    ("Instalar paquete (repos oficiales + AUR)", "yay -S <paquete>"),
    ("Sacar paquete + deps huérfanas + su config", "yay -Rns <paquete>"),
    ("Actualizar TODO el sistema (repos + AUR)", "yay"),
    ("Limpiar deps huérfanas que ya nadie usa", "yay -Rns (pacman -Qdtq)"),
]
for desc, key in PAQUETES:
    rows.add(row("[Paquetes]", desc, key))

# ---- SSH remoto + tmux (sesiones que sobreviven a la desconexión) ----
# El multiplexor corre EN EL SERVIDOR, no en tu máquina. Si se corta la
# conexión, la sesión sigue viva allá; volvés a entrar y reattachás.
SSH_REMOTO = [
    ("Crear / entrar a una sesión tmux", "tmux"),
    ("Crear sesión con nombre", "tmux new -s <nombre>"),
    ("Listar sesiones activas en el server", "tmux ls"),
    ("Reattach a la última sesión", "tmux attach   (o tmux a)"),
    ("Reattach a una sesión por nombre", "tmux attach -t <nombre>"),
    ("Desengancharse (dejar todo corriendo)", "Ctrl+b  luego  d"),
    ("Renombrar la sesión actual (estando adentro)", "Ctrl+b  luego  $"),
    ("Cerrar la sesión actual del todo", "exit"),
]
for desc, key in SSH_REMOTO:
    rows.add(row("[SSH remoto]", desc, key))

# ---- Neovim (LazyVim) — esenciales curados ----
# Leader = Espacio. Las teclas del "combo" se tipean en SECUENCIA (una tras otra),
# salvo las que dicen Ctrl/Alt (esas sí juntas). Extraídos de la config REAL
# (nvim_get_keymap), no de memoria. Para CUALQUIER atajo: dentro de nvim "Espacio s k".
NVIM = [
    # Esenciales (comandos de Vim de toda la vida: siempre funcionan)
    ("Esencial: guardar", ":w"),
    ("Esencial: guardar y salir", ":wq   (o ZZ)"),
    ("Esencial: salir / descartar", ":q     (descartar: :q!  o ZQ)"),
    ("Esencial: cancelar / salir de un modo", "Esc   (o Ctrl+c)"),
    ("Esencial: deshacer / rehacer", "u   /   Ctrl+r"),
    ("Esencial: copiar / pegar / cortar (Vim)", "y   /   p   /   d"),
    ("Esencial: empezar a escribir (modo insertar)", "i   (a = después del cursor)"),
    ("Esencial: buscar dentro del archivo", "/texto   (n / N = sig / ant)"),
    # Meta: cómo encontrar cualquier cosa sin memorizar
    ("Meta: BUSCAR cualquier atajo de nvim", "Espacio s k"),
    ("Meta: historial / paleta de comandos", "Espacio :"),
    ("Meta: ayuda de Neovim", "Espacio s h"),
    # Archivos y búsqueda
    ("Archivos: buscar archivo (raíz del proyecto)", "Espacio f f"),
    ("Archivos: buscar archivo (git)", "Espacio f g"),
    ("Archivos: recientes", "Espacio f r"),
    ("Archivos: grep de texto en el proyecto", "Espacio /   (o Espacio s g)"),
    ("Archivos: grep de la palabra bajo el cursor", "Espacio s w"),
    ("Archivos: buscar y reemplazar", "Espacio s r"),
    ("Archivos: proyectos", "Espacio f p"),
    # Exploradores de archivos
    ("Explorador: árbol de archivos (NeoTree)", "Espacio e"),
    ("Explorador: mini.files (carpeta del archivo)", "Espacio f m"),
    ("Explorador: Oil (editar la carpeta como texto)", "-"),
    ("Explorador: buffers abiertos", "Espacio ,   (o Espacio b e)"),
    # Ventanas (splits dentro de nvim)
    ("Ventanas: modo gestión (hydra)", "Ctrl+w"),
    ("Ventanas: diagnóstico bajo el cursor", "Ctrl+w d"),
    # Código / LSP
    ("Código: referencias del símbolo", "g r r   (preview: g p r)"),
    ("Código: ir a la definición (preview)", "g p d"),
    ("Código: implementación", "g r i   (preview: g p i)"),
    ("Código: type definition", "g r t"),
    ("Código: renombrar símbolo", "g r n"),
    ("Código: acción de código (quick fix)", "g r a"),
    ("Código: símbolos del documento", "g O"),
    ("Código: símbolos / outline", "Espacio c s"),
    ("Código: comentar / descomentar", "g c c   (selección: g c)"),
    ("Código: gestor de LSP/formatters (Mason)", "Espacio c m"),
    # Diagnóstico, TODOs
    ("Diagnóstico: siguiente / anterior", "] d   /   [ d"),
    ("Diagnóstico: lista (Trouble)", "Espacio x x"),
    ("Diagnóstico: lista (picker)", "Espacio s d"),
    ("TODO/FIX: siguiente / anterior", "] t   /   [ t"),
    ("TODO/FIX: listar todos", "Espacio s t"),
    # Git
    ("Git: estado (status)", "Espacio g s"),
    ("Git: diff de cambios (hunks)", "Espacio g d"),
    ("Git: explorador de git", "Espacio g e"),
    ("Git: stash", "Espacio g S"),
    # UI / varios
    ("UI: modo Zen (foco)", "Espacio z"),
    ("UI: cambiar tema (colorscheme)", "Espacio u C"),
    ("UI: descartar notificaciones", "Espacio u n"),
    ("UI: historial de notificaciones", "Espacio n"),
    ("UI: undotree (árbol de cambios)", "Espacio s u"),
    ("Sesiones: restaurar la última", "Espacio q l"),
    ("IA: Claude Code", "Espacio a"),
    ("Plugins: gestor (Lazy)", ":Lazy"),
    # Tuyos (definidos en lua/config/keymaps.lua)
    ("Tuyo: navegar splits nvim/tmux", "Ctrl+h / j / k / l"),
    ("Tuyo: borrar palabra sin salir de insertar", "Ctrl+b   (en modo insertar)"),
    ("Tuyo: Screenkey on/off", "Espacio u k"),
    ("Tuyo: cerrar otros buffers menos el actual", "Espacio b q"),
    ("Tuyo: Obsidian — nueva nota / buscar", "Espacio o n  /  Espacio o s"),
]
for desc, key in NVIM:
    rows.add(row("[Nvim]", desc, key))

print("\n".join(sorted(rows)))
