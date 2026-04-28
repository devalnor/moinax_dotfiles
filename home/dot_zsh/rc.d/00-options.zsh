# History
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000

# Type a directory name to cd into it
setopt autocd

# Emacs keymap (use `bindkey -v` for vi mode)
bindkey -e

# Word-jump and edit bindings
bindkey '^[[1;5C' forward-word        # Ctrl+Right
bindkey '^[[1;5D' backward-word       # Ctrl+Left
bindkey "\e[3~"   delete-char         # Delete
bindkey '\e[H'    beginning-of-line   # Home
bindkey '\e[F'    end-of-line         # End

# Editor
export EDITOR="nvim"
export VISUAL="cursor"
export SUDO_EDITOR="nvim"
