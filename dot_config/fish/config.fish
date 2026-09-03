if status is-interactive
    # Commands to run in interactive sessions can go here
    # Install Fisher if not installed
    if not functions -q fisher
        # This was `curl -sL https://git.io/fisher | source`. GitHub retired
        # git.io in 2022, so that shortlink no longer resolves at all: curl -s
        # printed nothing, `source` consumed an empty stream, and the next line
        # died with a confusing "unknown command: fisher" that says nothing about
        # the download having failed. A bootstrap that fails quietly is worse
        # than one that fails, so the fetch is checked and reported.
        #
        # -f makes curl fail on an HTTP error instead of piping an error page
        # into the shell, and -S keeps its message instead of swallowing it.
        set -l fisher_url https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
        set -l fisher_src (curl -fsSL --max-time 20 $fisher_url)
        set -l fetch_status $status
        if test $fetch_status -ne 0; or test -z "$fisher_src"
            echo "fisher bootstrap FAILED (curl exit $fetch_status): $fisher_url" >&2
            echo "fisher is not installed; install it manually before expecting plugins." >&2
        else
            printf '%s\n' $fisher_src | source
            fisher install jorgebucaran/fisher
        end
    end

end

# Detect Termux
set -l IS_TERMUX 0
if test -n "$TERMUX_VERSION"; or test -d /data/data/com.termux
    set IS_TERMUX 1
end

if test $IS_TERMUX -eq 1
    # Termux - use PREFIX for binaries
    set -x PATH $PREFIX/bin $HOME/.local/bin $HOME/.cargo/bin $PATH
else if test (uname) = Darwin
    # macOS - check for Apple Silicon vs Intel
    if test -f /opt/homebrew/bin/brew
        # Apple Silicon (M1/M2/M3)
        set BREW_BIN /opt/homebrew/bin/brew
    else if test -f /usr/local/bin/brew
        # Intel Mac
        set BREW_BIN /usr/local/bin/brew
    end
    set -x PATH $HOME/.local/bin $HOME/.opencode/bin $HOME/.volta/bin $HOME/.bun/bin $HOME/.nix-profile/bin /nix/var/nix/profiles/default/bin /usr/local/bin $HOME/.config $HOME/.cargo/bin /usr/local/lib/* $PATH
else
    # Linux
    set BREW_BIN /home/linuxbrew/.linuxbrew/bin/brew
    set -x PATH $HOME/.local/bin $HOME/.opencode/bin $HOME/.volta/bin $HOME/.bun/bin $HOME/.nix-profile/bin /nix/var/nix/profiles/default/bin /usr/local/bin $HOME/.config $HOME/.cargo/bin /usr/local/lib/* $PATH
end

# Only eval brew shellenv if brew is installed (not on Termux)
if test $IS_TERMUX -eq 0; and set -q BREW_BIN; and test -f $BREW_BIN
    eval ($BREW_BIN shellenv)
end

# Start tmux/zellij (tmux first, zellij as fallback)

# Initialize tools
starship init fish | source
zoxide init fish | source
atuin init fish | source
fzf --fish | source

# fnm — Fast Node Manager (user-owned Node, no sudo)
if type -q fnm
    fnm env --use-on-cd --shell fish | source
end

set -x PATH $HOME/.cargo/bin $PATH

# pnpm
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
if not contains -- "$PNPM_HOME/bin" $PATH
    set -gx PATH "$PNPM_HOME/bin" $PATH
end
# pnpm end

# Carapace completions
set -Ux CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'

if not test -d ~/.config/fish/completions
    mkdir -p ~/.config/fish/completions
end

if not test -f ~/.config/fish/completions/.initialized
    if not test -d ~/.config/fish/completions
        mkdir -p ~/.config/fish/completions
    end
    carapace --list | awk '{print $1}' | xargs -I{} touch ~/.config/fish/completions/{}.fish
    touch ~/.config/fish/completions/.initialized
end

carapace _carapace | source

set -g fish_greeting ""

# Enable vi mode
fish_vi_key_bindings

# Set nvim as default editor for opencode and other tools
set -gx EDITOR nvim
set -gx VISUAL nvim

## alias
# eza — modern ls replacement (icons, git status, grouped dirs)
alias ls='eza --icons=auto --group-directories-first'
alias ll='eza -la --icons=auto --git --group-directories-first'
alias la='eza -a --icons=auto --group-directories-first'
alias lt='eza --tree --level=2 --icons=auto --group-directories-first'

# claude — always launch in bypass permissions mode.
#
# `permissions.defaultMode: "bypassPermissions"` in ~/.claude/settings.json is
# unreliable: server-synced GrowthBook flags (tengu_quill_harbor: "acceptEdits",
# tengu_permission_friction) silently override it at session start, so sessions
# land in Accept Edits and prompt on every Bash command. See
# https://github.com/anthropics/claude-code/issues/39523 — open, unresolved.
#
# The CLI flag is resolved before that override, so it holds. An abbr rather
# than an alias keeps the flag visible and editable on the command line for the
# times you'd rather not have it.
abbr -a claude 'claude --dangerously-skip-permissions'

alias fzfbat='fzf --preview="bat --theme=gruvbox-dark --color=always {}"'
alias fzfnvim='nvim (fzf --preview="bat --theme=gruvbox-dark --color=always {}")'

set -l foreground F3F6F9 normal
set -l selection 263356 normal
set -l comment 8394A3 brblack
set -l red CB7C94 red
set -l orange DEBA87 orange
set -l yellow FFE066 yellow
set -l green B7CC85 green
set -l purple A3B5D6 purple
set -l cyan 7AA89F cyan
set -l pink FF8DD7 magenta

# Syntax Highlighting Colors
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $pink
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $pink
set -g fish_color_autosuggestion $comment

# Completion Pager Colors
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment
clear
