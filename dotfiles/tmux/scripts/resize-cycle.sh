#!/bin/bash
# Cycle current pane size through 1/3, 1/2, 2/3 of window dimension.
# Usage: resize-cycle.sh W|H  (W = width axis, H = height axis)

axis="$1"
pane=$(tmux display -p '#{pane_id}')

case "$axis" in
    W) opt="@resize_w_idx"; dim="window_width";  flag="-x" ;;
    H) opt="@resize_h_idx"; dim="window_height"; flag="-y" ;;
    *) echo "axis must be W or H" >&2; exit 1 ;;
esac

idx=$(tmux show -pqv "$opt" 2>/dev/null)
[[ -z "$idx" ]] && idx=-1
idx=$(( (idx + 1) % 3 ))
tmux set -pq "$opt" "$idx"

# fractions: 1/3, 1/2, 2/3
nums=(1 1 2)
dens=(3 2 3)

total=$(tmux display -p "#{$dim}")
target=$(( total * ${nums[$idx]} / ${dens[$idx]} ))

tmux resize-pane "$flag" "$target"
