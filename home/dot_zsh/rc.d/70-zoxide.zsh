# zoxide: smart cd. Must be the last `eval` to avoid
# "possible configuration issue" warnings about precmd hooks.
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh --cmd cd)"
fi
