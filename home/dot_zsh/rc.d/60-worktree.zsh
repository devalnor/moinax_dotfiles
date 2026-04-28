# WorkTrunk shell integration (cd's parent shell on `wt switch`)
if command -v wt &> /dev/null; then
  eval "$(command wt config shell init zsh)"
fi

# Create/switch worktree, then launch a kitty dev environment in it.
# Stays a function (not a script) because `wt switch` requires shell integration.
wtstart() {
  local branch="$1"
  local is_new=false
  local orig_dir="$PWD"

  if [[ -z "$branch" ]]; then
    wt switch || return 1
    [[ "$PWD" == "$orig_dir" ]] && return 0
  else
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      wt switch "$branch" || {
        echo "error: failed to switch to worktree for '$branch'" >&2
        return 1
      }
    else
      wt switch --create "$branch" || {
        echo "error: failed to create worktree for '$branch'" >&2
        return 1
      }
      is_new=true
    fi

    # Copy gitignored files (e.g. .env.development.local) for new worktrees only
    if $is_new; then
      wt step copy-ignored
    fi
  fi

  local name="${branch:-$(git branch --show-current)}"
  local dir="$PWD"

  kitty --title "$name" --directory "$dir" --session <(kdev-session -n "$name") &>/dev/null & disown

  builtin cd -- "$orig_dir"
}

alias wts=wtstart
alias wtc=wtclean      # standalone script in ~/.local/bin
alias wtu=wtupdate     # standalone script in ~/.local/bin
