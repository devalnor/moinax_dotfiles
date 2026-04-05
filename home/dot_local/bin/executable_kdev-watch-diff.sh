#!/bin/bash
# Auto-updating git diff for kdev/wts split layout.
# Watches for file changes and re-runs git diff HEAD through delta.

refresh() {
    clear
    local has_diff=0 untracked
    git diff --quiet HEAD 2>/dev/null || has_diff=1
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null)

    if (( has_diff )); then
        git diff HEAD
    fi
    if [ -n "$untracked" ]; then
        (( has_diff )) && echo
        echo -e "\033[1;33mUntracked files:\033[0m"
        echo "$untracked"
    fi
    if (( !has_diff )) && [ -z "$untracked" ]; then
        echo -e "\033[2m-- No uncommitted changes --\033[0m"
    fi
}

watch_with_inotify() {
    inotifywait -r -m -q -e close_write,create,delete,move \
        --exclude '(/\.git/|/node_modules/)' . 2>/dev/null |
    while read _; do
        # Debounce: drain remaining events within 300ms
        while read -t 0.3 _; do :; done
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
