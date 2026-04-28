# Source the first existing path from a list of candidates.
_source_first() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && { source "$f"; return 0; }
  done
  return 1
}

# zsh-autosuggestions (Arch and Fedora package layouts)
_source_first \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#696969"

# zsh-syntax-highlighting (Arch and Fedora package layouts)
_source_first \
  /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

unfunction _source_first
