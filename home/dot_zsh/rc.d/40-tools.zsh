# starship prompt
if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi

# television: CTRL+T file picker, CTRL+R history search
if command -v tv &> /dev/null; then
  eval "$(tv init zsh)"

  # Override smart autocomplete so an empty prompt launches `tv files`
  # instead of zsh's expand-or-complete (which would offer "5500 possibilities").
  _tv_smart_autocomplete() {
    _disable_bracketed_paste
    local tokens prefix lbuf
    setopt localoptions noshwordsplit noksh_arrays noposixbuiltins

    tokens=(${(z)LBUFFER})
    if [ ${#tokens} -lt 1 ]; then
      zle -I
      local output
      output=$(tv files --no-status-bar --inline < /dev/tty)
      if [ -n "$output" ]; then
        LBUFFER="${(q)output} "
      fi
      zle reset-prompt
      _enable_bracketed_paste
      return
    fi

    [[ ${LBUFFER[-1]} == ' ' ]] && tokens+=("")
    if [[ ${LBUFFER} = *"${tokens[-2]-}${tokens[-1]}" ]]; then
      tokens[-2]="${tokens[-2]-}${tokens[-1]}"
      tokens=(${tokens[0,-2]})
    fi

    lbuf=$LBUFFER
    prefix=${tokens[-1]}
    [ -n "${tokens[-1]}" ] && lbuf=${lbuf:0:-${#tokens[-1]}}
    __tv_path_completion "$prefix" "$lbuf"
    _enable_bracketed_paste
  }
fi

# keychain: hold ssh key for git/etc. -q silences the status banner.
if command -v keychain &> /dev/null; then
  # If the inherited SSH_AUTH_SOCK points to a dead agent (exit 2 from
  # ssh-add -l means "could not connect"), unset it so keychain falls
  # back to its own cache instead of trusting the stale socket. Do NOT
  # wipe keychain's cache here — that would kill the live agent other
  # shells are using and force a fresh passphrase prompt.
  if [[ -n "$SSH_AUTH_SOCK" ]]; then
    ssh-add -l &>/dev/null
    [[ $? -eq 2 ]] && unset SSH_AUTH_SOCK SSH_AGENT_PID
  fi
  eval "$(keychain --eval --quiet id_ed25519)"
fi
