#!/bin/bash
# Auto-updating git diff for kdev/wts split layout.
# Watches for file changes and re-runs git diff HEAD through delta.

refresh() {
    clear
    git diff HEAD
}

watch_with_inotify() {
    inotifywait -r -m -q -e close_write,create,delete,move \
        --exclude '(\.git/(objects|logs)|node_modules)' . 2>/dev/null |
    while read -t 0.3 _; do
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
