#!/usr/bin/env bash
# Select next/prev pane in clockwise spatial order.
# Usage: pane-cycle-clockwise.sh <next|prev>
#   next = clockwise, prev = counter-clockwise
#
# tmux pane indices follow tree order, not screen position, so cycling by
# index (:.+ / :.-) jumps around visually. This script sorts panes by angle
# from the window centroid (screen coords, y-down → clockwise = ascending
# angle after rotating origin to "up"), then steps to the neighbor of the
# current pane in that order.

set -eu

dir="${1:?direction required: next|prev}"

current=$(tmux display -p '#{pane_id}')

panes_raw=$(tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}')

# Sort by clockwise angle from window centroid; emit just pane_ids in order.
order_str=$(awk -v current="$current" '
  {
    id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5;
    cx_sum += $2 + $4/2;
    cy_sum += $3 + $5/2;
    n = NR;
  }
  END {
    pi = 3.14159265358979;
    cx = cx_sum / n;
    cy = cy_sum / n;
    for (i = 1; i <= n; i++) {
      px = l[i] + w[i]/2;
      py = t[i] + h[i]/2;
      a = atan2(py - cy, px - cx) + pi/2;
      if (a < 0) a += 2*pi;
      if (a >= 2*pi) a -= 2*pi;
      printf "%.6f %s\n", a, id[i];
    }
  }
' <<<"$panes_raw" | sort -n | awk '{print $2}')

# Build array and find current index.
order=()
while IFS= read -r pid; do order+=("$pid"); done <<<"$order_str"
n=${#order[@]}
if [ "$n" -le 1 ]; then exit 0; fi

idx=-1
for i in "${!order[@]}"; do
  if [ "${order[$i]}" = "$current" ]; then idx=$i; break; fi
done
if [ "$idx" -lt 0 ]; then exit 0; fi

case "$dir" in
  next) target=${order[$(( (idx + 1) % n ))]} ;;
  prev) target=${order[$(( (idx - 1 + n) % n ))]} ;;
  *) echo "unknown direction: $dir" >&2; exit 2 ;;
esac

tmux select-pane -t "$target"
