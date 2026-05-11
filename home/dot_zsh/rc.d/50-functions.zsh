# Launch a kitty dev environment (Claude splits + Neovim tabs) for a directory
kdev() {
  local name_override=""
  while [[ "$1" == -* ]]; do
    case "$1" in
      -n)
        [[ -z "$2" || "$2" == -* ]] && { echo "kdev: -n requires a name" >&2; return 1; }
        name_override="$2"; shift 2 ;;
      --) shift; break ;;
      *) echo "kdev: unknown option $1" >&2; return 1 ;;
    esac
  done
  local dir="${1:-.}"
  dir="$(cd "$dir" && pwd)"
  local name="${name_override:-$(basename "$dir")}"
  kitty --title "$name" --directory "$dir" --session <(kdev-session -n "$name") &>/dev/null & disown
}

# yazi wrapper that cd's the parent shell to yazi's exit cwd
y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}
