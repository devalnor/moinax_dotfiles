# Launch a kitty dev environment (Claude splits + Neovim tabs) for a directory
kdev() {
  local dir="${1:-.}"
  dir="$(cd "$dir" && pwd)"
  local name="$(basename "$dir")"
  kitty --title "$name" --directory "$dir" --session <(kdev-session) &>/dev/null & disown
}

# yazi wrapper that cd's the parent shell to yazi's exit cwd
y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}
