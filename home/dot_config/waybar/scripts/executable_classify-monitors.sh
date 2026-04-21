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
    niri msg -j outputs | jq -c '
      [to_entries[] | select(.value.current_mode != null and .value.logical != null) | {
        name: .key,
        eff: (
          .value.current_mode as $m |
          .value.logical as $l |
          (if (($l.transform // "normal") | tostring | test("90|270"))
            then $m.height else $m.width end)
          / (($l.scale // 1) | tonumber)
        )
      }] |
      { wide:   [.[] | select(.eff >= 1920) | .name],
        narrow: [.[] | select(.eff <  1920) | .name] }'
    ;;
  *)
    echo "unknown compositor: $COMPOSITOR (expected hyprland or niri)" >&2
    exit 2
    ;;
esac
