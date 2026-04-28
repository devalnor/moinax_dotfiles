# Welcome banner: only on a top-level shell in a real terminal emulator.
# Embedded terminals (VS Code, Cursor, WebStorm, Claude Code, nvim :term) inherit
# TERM=xterm-256color from their parent and won't match this allowlist.
if command -v fastfetch &> /dev/null && [[ $SHLVL -eq 1 ]]; then
  case "$TERM" in
    xterm-kitty|alacritty*|wezterm|foot*|xterm-ghostty) fastfetch ;;
  esac
fi

# Local overrides not managed by chezmoi.
# Installers (bun, cargo, etc.) can safely append to ~/.zshrc.local.
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
