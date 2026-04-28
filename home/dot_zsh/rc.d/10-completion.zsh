# Completion
zstyle ':completion:*' completer _complete _ignored
zstyle ':completion:*:default' menu select=0
zstyle :compinstall filename "$HOME/.zshrc"

# Git completion + custom completions
zstyle ':completion:*:*:git:*' script ~/.zsh/git-completion.bash
fpath=(~/.zsh ~/.zsh/completions $fpath)

autoload -Uz compinit
compinit

# pnpm
[[ -f ~/completion-for-pnpm.bash ]] && source ~/completion-for-pnpm.bash

# fnm
if command -v fnm &> /dev/null; then
  eval "$(fnm completions --shell zsh)"
fi
