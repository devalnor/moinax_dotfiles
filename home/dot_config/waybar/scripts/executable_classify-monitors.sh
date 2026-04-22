#!/usr/bin/env bash
# Classify connected monitors by effective width (post-scale, post-rotation).
# Emits {"wide":[...],"narrow":[...]} on stdout.
# Threshold: effective width >= 1920 is "wide".

set -euo pipefail

COMPOSITOR="${1:?compositor arg required: hyprland or niri}"

case "$COMPOSITOR" in
  hyprland)
    hyprctl -j monitors | jq -c '
      def eff: if (.transform % 2 == 1) then (.height / .scale) else (.width / .scale) end;
      [.[] | select(.disabled | not)] as $active |
      { wide:   [$active[] | select((eff) >= 1920) | .name],
        narrow: [$active[] | select((eff) <  1920) | .name] }'
    ;;
  niri)
    # niri's `logical` rect is already post-scale and post-rotation, so we use
    # it directly. `current_mode` is an integer index into `modes`, not an
    # object — don't try to deref fields on it.
    niri msg -j outputs | jq -c '
      [to_entries[] | select(.value.logical != null) | {
        name: .key,
        eff: .value.logical.width
      }] |
      { wide:   [.[] | select(.eff >= 1920) | .name],
        narrow: [.[] | select(.eff <  1920) | .name] }'
    ;;
  *)
    echo "unknown compositor: $COMPOSITOR (expected hyprland or niri)" >&2
    exit 2
    ;;
esac
