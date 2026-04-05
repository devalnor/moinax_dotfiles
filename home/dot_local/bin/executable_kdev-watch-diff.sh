#!/bin/bash
# Auto-updating git diff for kdev/wts split layout.
# Watches for file changes and displays git diff HEAD through delta.

set -euo pipefail

BOLD_YELLOW=$(tput bold)$(tput setaf 3)
DIM=$(tput dim)
RST=$(tput sgr0)

PREV_HASH=""
FORCE_REFRESH=0

trap 'FORCE_REFRESH=1' SIGWINCH

refresh() {
    local raw_diff untracked new_hash
    raw_diff=$(git diff HEAD 2>/dev/null) || true
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null) || true
    new_hash=$(printf '%s\n%s' "$raw_diff" "$untracked" | md5sum)

    if [[ "$new_hash" == "$PREV_HASH" ]] && (( !FORCE_REFRESH )); then
        return
    fi
    PREV_HASH="$new_hash"
    FORCE_REFRESH=0

    printf '\033[H\033[2J\033[3J'

    if [[ -n "$raw_diff" ]]; then
        git diff HEAD
    fi
    if [[ -n "$untracked" ]]; then
        [[ -n "$raw_diff" ]] && echo
        echo "${BOLD_YELLOW}Untracked files:${RST}"
        echo "$untracked"
    fi
    if [[ -z "$raw_diff" ]] && [[ -z "$untracked" ]]; then
        echo "${DIM}-- No uncommitted changes --${RST}"
    fi
}

watch_with_inotify() {
    inotifywait -r -m -q -e close_write,create,delete,move \
        --exclude '(/\.git/|/node_modules/)' . 2>/dev/null |
    while read -r _; do
        while read -r -t 0.3 _; do :; done
        refresh
    done
}

refresh

if command -v inotifywait &>/dev/null; then
    while true; do
        watch_with_inotify
        sleep 1
    done
else
    while sleep 2; do
        refresh
    done
fi
