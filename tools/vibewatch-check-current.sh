#!/usr/bin/env bash
# Exit 0 when vibewatch is installed and the embedded build SHA matches
# `git ls-remote HEAD` for the upstream repo (or the remote is unreachable,
# in which case we trust the local install). Exit 1 otherwise.
#
# With --print-sha, writes the local SHA to stdout so callers can reuse it
# without re-spawning `vibewatch --version`. Used as the `check` field in
# packages/groups/ai.yaml (silent) and as the gate in `do_update` (with
# --print-sha).
set -u

print_sha=false
[ "${1:-}" = "--print-sha" ] && print_sha=true

command -v vibewatch >/dev/null 2>&1 || exit 1

local_sha=$(vibewatch --version 2>/dev/null | awk '{print $NF}' | tr -d '()')
[ -n "$local_sha" ] || exit 1
$print_sha && echo "$local_sha"

remote_sha=$(git ls-remote https://github.com/Moinax/vibewatch.git HEAD 2>/dev/null | cut -f1)
[ -z "$remote_sha" ] && exit 0

[[ "$remote_sha" == "$local_sha"* ]]
